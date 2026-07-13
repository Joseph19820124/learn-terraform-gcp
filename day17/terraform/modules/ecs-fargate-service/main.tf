# modules/ecs-fargate-service/main.tf —— day08 模块的扩展版：
#   1) ALB 变成可选(var.create_alb) —— callee 不需要公网入口，不建 ALB。
#   2) 加了 ECS Service Connect 配置 —— 服务之间靠内部短名字互相调用。
#   3) 加了 allowed_security_group_ids —— 显式声明"谁能连我"，而不是对全世界开放。

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

# ---------- 安全组 ----------
# 和 day08 的关键区别:day08 只有"对全世界开放"或"不开放"两种；
# 这里加了第三种 —— "只对指定的安全组开放"，用来表达
# "只有 caller 能连 callee，其他人一概不行"这种精细的访问控制。
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

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      from_port       = var.container_port
      to_port         = var.container_port
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- ALB(可选) ----------
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
  count       = var.create_alb ? 1 : 0
  name        = "${var.name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  # 比 day08 短很多的 deregistration delay —— day08 用默认 300 秒，
  # destroy 时卡了 5-6 分钟。学习环境没必要保留生产级的优雅下线时间。
  deregistration_delay = 30

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

# ---------- Task 定义 + Service ----------
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
        # Service Connect 靠这个 name 字段做端口引用(下面 service_connect_configuration
        # 的 port_name 要和这里对上)，不是靠端口号本身。
        name          = var.container_port_name
        containerPort = var.container_port
        protocol      = "tcp"
      }]
      environment = [
        for k, v in var.environment : { name = k, value = v }
      ]
      dockerLabels = var.docker_labels
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
    subnets = var.subnet_ids
    # 这个 demo 用 default VPC 的公有子网、没建 NAT，所有 task(包括 callee)
    # 都需要公网 IP 才能出网拉镜像/连 CloudWatch —— 但"有公网 IP"不等于
    # "外面能连进来"，真正挡住外部访问的是上面的安全组规则。
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true
  }

  dynamic "load_balancer" {
    for_each = var.create_alb ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = "main"
      container_port   = var.container_port
    }
  }

  # Service Connect 配置:所有服务都要 enabled=true 才能"发起"对其他
  # Service Connect 服务的调用；只有想"被别人按名字调用"的服务才需要
  # 声明下面的 service{} 块(比如 callee 声明了，caller 没声明)。
  service_connect_configuration {
    enabled   = var.enable_service_connect
    namespace = var.namespace_arn

    dynamic "service" {
      for_each = var.service_connect_name != "" ? [1] : []
      content {
        port_name      = var.container_port_name
        discovery_name = var.service_connect_name

        client_alias {
          port     = var.container_port
          dns_name = var.service_connect_name
        }
      }
    }
  }

  # 引用整个 aws_lb_listener.http(count 资源，create_alb=false 时是空列表)：
  # 有 ALB 时必须等 listener 建好 service 才能注册；没 ALB 时这行就是空依赖，无副作用。
  depends_on = [aws_lb_listener.http]
}
