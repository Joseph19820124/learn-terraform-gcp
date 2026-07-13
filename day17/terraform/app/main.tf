# app/main.tf —— day09 的改造版：caller 不再挂自己的 ALB，改成一个独立的
# Traefik ECS 服务做反向代理 + 动态服务发现(读 caller 容器的 dockerLabels
# 生成路由规则)，Traefik 前面挂一个 NLB(L4，纯转发，不做任何路由决策)。
# callee 不变，还是纯内部服务，只能被 caller 按 Service Connect 名字调用。

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

module "cluster" {
  source = "../modules/ecs-cluster"
  name   = var.name
  vpc_id = data.aws_vpc.default.id
}

# ---------- callee:纯内部服务，没有 ALB，只能被 caller 按 Service Connect 名字调用 ----------
module "callee" {
  source = "../modules/ecs-fargate-service"

  name          = "${var.name}-callee"
  region        = var.region
  vpc_id        = data.aws_vpc.default.id
  subnet_ids    = data.aws_subnets.default.ids
  cluster_id    = module.cluster.cluster_id
  namespace_arn = module.cluster.namespace_arn

  container_image = var.callee_image
  create_alb      = false

  # 声明这个名字，caller 才能用 "http://callee:8080" 找到它。
  service_connect_name = "callee"

  # 只放行 caller 的安全组，其他人(包括公网)一律连不上 —— 这是这一天
  # 想讲的核心:内部服务互调不代表要对外暴露，安全组照样按最小暴露面设计。
  allowed_security_group_ids = [module.caller.service_security_group_id]
}

# ---------- caller:不再自己挂 ALB，靠 Traefik 的 ECS provider 动态发现 ----------
module "caller" {
  source = "../modules/ecs-fargate-service"

  name          = "${var.name}-caller"
  region        = var.region
  vpc_id        = data.aws_vpc.default.id
  subnet_ids    = data.aws_subnets.default.ids
  cluster_id    = module.cluster.cluster_id
  namespace_arn = module.cluster.namespace_arn

  container_image = var.caller_image
  create_alb      = false

  # caller 不需要被别人按名字调用，所以 service_connect_name 留空；
  # 但 enable_service_connect 默认是 true，这样它才能"发起"对 callee 的调用。
  environment = {
    CALLEE_URL = "http://callee:8080"
  }

  # Traefik 的 ECS provider 靠这些 label 生成路由规则，等价于 Docker
  # provider 读容器 label 那一套——ALB 时代靠 target group + listener rule
  # 显式声明"谁转发给谁"，这里换成"caller 自己声明我要被路由"。
  docker_labels = {
    "traefik.enable"                                        = "true"
    "traefik.http.routers.caller.rule"                      = "PathPrefix(`/`)"
    "traefik.http.services.caller.loadbalancer.server.port" = "8080"
  }

  # 只放行 Traefik 的安全组——和 day09 里 callee 只放行 caller 的安全组是
  # 同一个思路，只是这次换成"公网入口"这一层也照样最小暴露面。
  allowed_security_group_ids = [aws_security_group.traefik.id]
}

# ==================== Traefik:用来替代 ALB 的反向代理 ====================
# 原计划是 Internet → NLB(纯 L4 转发)→ Traefik → caller，真实部署时
# NLB 创建被拒:"This AWS account currently does not support creating
# load balancers"——不是配额问题(Network Load Balancers per Region 配额
# 显示 50，一个没用)，是 AWS 对这个账号第一次创建 NLB 这个资源类型的
# 自动信任审核卡住了，跟这个账号已经成功建过一堆 ALB(day08 到 day16)
# 是两码事——ALB 和 NLB 的信任审核是分开走的。没有 Support 订阅，没法用
# API 开工单人工解除，于是改成 Internet → ALB(只做入口/L4，不写死任何
# 路由规则)→ Traefik(读 ECS API 动态发现 caller，真正做 L7 路由决策)
# → caller。核心教学点不变：ALB 版本的路由规则是 Terraform 里写死的
# target group/listener rule；这一版路由规则是 caller 自己用
# dockerLabels 声明出来的，Traefik 运行时轮询 ECS API 动态生成——只是
# 前面多了一层 AWS 自己的负载均衡器做公网入口，没有 100% 甩掉 AWS LB。

resource "aws_iam_role" "traefik_task" {
  name = "${var.name}-traefik-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Traefik 的 ECS provider 要能读 ECS/EC2 的描述性 API 才能发现服务——这是
# 任务角色(运行时权限)，不是执行角色(拉镜像/写日志用的那个)。
# ssm:DescribeInstanceInformation 只有 ECS Anywhere 才需要，这里纯 Fargate
# 用不上，故意不给。
resource "aws_iam_role_policy" "traefik_ecs_discovery" {
  name = "${var.name}-traefik-ecs-discovery"
  role = aws_iam_role.traefik_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecs:ListClusters",
        "ecs:DescribeClusters",
        "ecs:ListTasks",
        "ecs:DescribeTasks",
        "ecs:DescribeContainerInstances",
        "ecs:DescribeTaskDefinition",
        "ec2:DescribeInstances",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "traefik_execution" {
  name = "${var.name}-traefik-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "traefik_execution" {
  role       = aws_iam_role.traefik_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "traefik" {
  name              = "/ecs/${var.name}-traefik"
  retention_in_days = 3
}

resource "aws_security_group" "traefik_alb" {
  name        = "${var.name}-traefik-alb-sg"
  description = "ALB in front of Traefik"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "traefik" {
  name        = "${var.name}-traefik-sg"
  description = "Traefik ECS service"
  vpc_id      = data.aws_vpc.default.id

  # 只放行 ALB 的安全组——和 day09 里 ALB→service 那条规则完全一样的写法，
  # ALB 是唯一能直接碰到 Traefik 80 端口的东西。
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.traefik_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "traefik" {
  name               = "${var.name}-traefik-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.traefik_alb.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "traefik" {
  name        = "${var.name}-traefik-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  deregistration_delay = 30

  # 打 /health——会原样经 Traefik 转发给 caller(PathPrefix('/') 覆盖
  # 所有路径)，caller 的 /health handler 返回 200。不能打 "/"：caller
  # 没有定义这个路径，Spring Boot 会回 404，ALB 健康检查就会一直不健康。
  health_check {
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
    timeout             = 5
  }
}

resource "aws_lb_listener" "traefik" {
  load_balancer_arn = aws_lb.traefik.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.traefik.arn
  }
}

resource "aws_ecs_task_definition" "traefik" {
  family                   = "${var.name}-traefik"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.traefik_execution.arn
  task_role_arn            = aws_iam_role.traefik_task.arn

  container_definitions = jsonencode([
    {
      name      = "traefik"
      image     = "traefik:v3.3"
      essential = true
      portMappings = [{
        name          = "web"
        containerPort = 80
        protocol      = "tcp"
      }]
      command = [
        "--entrypoints.web.address=:80",
        "--providers.ecs=true",
        "--providers.ecs.region=${var.region}",
        "--providers.ecs.clusters=${var.name}-cluster",
        "--providers.ecs.autoDiscoverClusters=false",
        "--providers.ecs.exposedByDefault=false",
        # 默认日志级别是 ERROR，连启动横幅都看不到——为了能在 CloudWatch
        # 里实际看到 ECS provider 发现了什么，显式调到 INFO。
        "--log.level=INFO",
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.traefik.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "traefik" {
  name            = "${var.name}-traefik"
  cluster         = module.cluster.cluster_id
  task_definition = aws_ecs_task_definition.traefik.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.traefik.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.traefik.arn
    container_name   = "traefik"
    container_port   = 80
  }

  health_check_grace_period_seconds = 60

  depends_on = [aws_lb_listener.traefik]
}
