# modules/ecs-lattice-service/main.tf —— day09 ecs-fargate-service 模块的
# VPC Lattice 版本。ALB 部分完全不变；把 Service Connect 那一块换成了
# VPC Lattice 的一整套资源(target group + service + listener + 网络关联)。
#
# 和 day09 最大的架构差异 —— 安全组规则怎么写:
#   day09(Service Connect):callee 的安全组直接放行 caller 的安全组 ID，
#                            因为流量是 caller 的 ENI 直接连到 callee 的 ENI。
#   day10(VPC Lattice)     ：不能这样写！VPC Lattice 的流量走 AWS 托管的
#                            Lattice 数据面，不是从 caller 的 ENI 直接过来的。
#                            必须放行 AWS 托管的 VPC Lattice prefix list。
# 这是文档里明确写的限制:"You can't use the client security group as a
# source for your target's security groups... you must reference the
# VPC Lattice managed prefix list directly."

data "aws_ec2_managed_prefix_list" "vpc_lattice" {
  count = var.expose_via_lattice ? 1 : 0
  name  = "com.amazonaws.${var.region}.vpc-lattice"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = 3
}

resource "aws_iam_role" "execution" {
  name = "${var.name}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------- VPC Lattice 专用:ECS "基础设施角色" ----------
# 这是 day09 完全没有的东西。ECS 要替你把 Fargate task 的动态 IP
# 自动注册/注销到 VPC Lattice 的目标组里(类似它天然就会对 ALB target group
# 做的事)，但这个能力对 Lattice 来说需要一个显式的 IAM 角色，
# 不像 ALB 那样是内置行为。
resource "aws_iam_role" "ecs_infrastructure" {
  count = var.expose_via_lattice ? 1 : 0
  name  = "${var.name}-ecs-infra-lattice"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_infrastructure" {
  count      = var.expose_via_lattice ? 1 : 0
  role       = aws_iam_role.ecs_infrastructure[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForVpcLattice"
}

# ---------- 安全组 ----------
resource "aws_security_group" "service" {
  name        = "${var.name}-sg"
  description = "Security group for ${var.name}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.create_alb ? [1] : []
    content {
      from_port       = var.container_port
      to_port         = var.container_port
      protocol        = "tcp"
      security_groups = [aws_security_group.alb[0].id]
    }
  }

  # 关键对比点:这里放行的是 AWS 托管 prefix list，不是某个具体的安全组。
  dynamic "ingress" {
    for_each = var.expose_via_lattice ? [1] : []
    content {
      from_port       = var.container_port
      to_port         = var.container_port
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.vpc_lattice[0].id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- ALB(可选，和 day09 完全一样) ----------
resource "aws_security_group" "alb" {
  count       = var.create_alb ? 1 : 0
  name        = "${var.name}-alb-sg"
  description = "ALB security group for ${var.name}"
  vpc_id      = var.vpc_id

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

resource "aws_lb" "this" {
  count              = var.create_alb ? 1 : 0
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = var.subnet_ids
}

resource "aws_lb_target_group" "this" {
  count                 = var.create_alb ? 1 : 0
  name                  = "${var.name}-tg"
  port                  = var.container_port
  protocol              = "HTTP"
  vpc_id                = var.vpc_id
  target_type           = "ip"
  deregistration_delay  = 30

  health_check {
    path                = var.health_check_path
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
    timeout             = 5
  }
}

resource "aws_lb_listener" "http" {
  count             = var.create_alb ? 1 : 0
  load_balancer_arn = aws_lb.this[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }
}

# ---------- VPC Lattice:目标组 + 服务 + 监听器 + 网络关联 ----------
# 只有 expose_via_lattice=true(callee)才会创建这一整套。
resource "aws_vpclattice_target_group" "this" {
  count = var.expose_via_lattice ? 1 : 0
  name  = "${var.name}-tg"
  type  = "IP"

  config {
    vpc_identifier   = var.vpc_id
    ip_address_type  = "IPV4"
    port             = var.container_port
    protocol         = "HTTP"
    protocol_version = "HTTP1"

    health_check {
      enabled  = true
      path     = var.health_check_path
      port     = var.container_port
      protocol = "HTTP"
    }
  }
}

resource "aws_vpclattice_service" "this" {
  count     = var.expose_via_lattice ? 1 : 0
  name      = var.name
  auth_type = "NONE" # 简化起见不做 IAM 签名校验;生产环境建议 AWS_IAM
}

resource "aws_vpclattice_listener" "this" {
  count               = var.expose_via_lattice ? 1 : 0
  name                = "http"
  protocol            = "HTTP"
  service_identifier  = aws_vpclattice_service.this[0].id

  default_action {
    forward {
      target_groups {
        target_group_identifier = aws_vpclattice_target_group.this[0].id
      }
    }
  }
}

# 把这个服务"发布"到服务网络里，别的接入了同一个网络的资源才能发现它。
resource "aws_vpclattice_service_network_service_association" "this" {
  count                       = var.expose_via_lattice ? 1 : 0
  service_identifier          = aws_vpclattice_service.this[0].id
  service_network_identifier  = var.lattice_service_network_id
}

# ---------- Task 定义 + ECS Service ----------
resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn

  container_definitions = jsonencode([
    {
      name      = "main"
      image     = var.container_image
      essential = true
      portMappings = [{
        name          = var.container_port_name
        containerPort = var.container_port
        protocol      = "tcp"
      }]
      environment = [
        for k, v in var.environment : { name = k, value = v }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets           = var.subnet_ids
    security_groups   = [aws_security_group.service.id]
    assign_public_ip  = true
  }

  # 挂了 ALB 才需要:给容器一段"启动宽限期"，宽限期内 ALB 健康检查失败
  # 不会被算作真的不健康、不会杀掉这个 task。没设这个的话，Spring Boot
  # 的 JVM 冷启动很容易输给 target group 15 秒/2 次的健康检查窗口，
  # 应用还没跑起来就被判定失败、反复被杀重建 —— 这是本 day 实测踩到的坑。
  health_check_grace_period_seconds = var.create_alb ? 60 : null

  dynamic "load_balancer" {
    for_each = var.create_alb ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = "main"
      container_port   = var.container_port
    }
  }

  # ECS 原生的 VPC Lattice 集成(2024年11月才加的能力):替代 day09 里的
  # service_connect_configuration block。有了这个，ECS 会自动把这个
  # service 每次伸缩/重建产生的新 task IP 注册进上面那个 Lattice 目标组，
  # 不用你手动维护。
  dynamic "vpc_lattice_configurations" {
    for_each = var.expose_via_lattice ? [1] : []
    content {
      port_name         = var.container_port_name
      role_arn          = aws_iam_role.ecs_infrastructure[0].arn
      target_group_arn  = aws_vpclattice_target_group.this[0].arn
    }
  }

  depends_on = [aws_lb_listener.http]
}
