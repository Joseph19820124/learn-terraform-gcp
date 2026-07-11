# modules/ecs-fargate-service/main.tf —— day09 模块的扩展版：
# 加了一个可选的 FireLens 开关(var.enable_firelens)。开了之后：
#   1) 主容器的 logConfiguration 从 awslogs(CloudWatch)换成 awsfirelens。
#   2) 任务里多一个 log_router sidecar 容器(aws-for-fluent-bit)，
#      拦截主容器的 stdout/stderr，转发到 Loki(用 Fluent Bit 内置的
#      原生 loki output，不是社区维护的 grafana/fluent-bit-plugin-loki
#      镜像——aws-for-fluent-bit:3 系列基于 Fluent Bit 4.x，早就自带了)。
# Loki/Grafana 这两个服务本身不需要 FireLens，直接复用这个模块、
# enable_firelens 保持默认 false 就行(它们自己的容器日志走 CloudWatch)。

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
locals {
  main_container_base = {
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
    # 关键点:主容器的日志驱动在这里二选一。原来(day09)只有 awslogs 一条路，
    # 这一天加了 awsfirelens 这条路——由 log_router sidecar 接管日志，
    # 转发去 Loki，而不是 CloudWatch。
    logConfiguration = var.enable_firelens ? {
      logDriver = "awsfirelens"
      options = {
        Name        = "loki"
        Host        = var.loki_host
        Port        = tostring(var.loki_port)
        Labels      = "job=${var.name}"
        Label_Keys  = "$container_name"
        Line_Format = "key_value"
      }
    } : {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }

  # dependsOn 用三元表达式给"空列表"而不是省略这个 key——实测踩过一次坑:
  # 三元表达式两个分支的 object 必须是同一个类型(同一组 key),一边有
  # dependsOn 一边没有会直接报 "Inconsistent conditional result types"。
  # 空列表在语义上等价于"没有依赖",ECS API 也认。
  main_container = merge(local.main_container_base, {
    dependsOn = var.enable_firelens ? [{ containerName = "log_router", condition = "START" }] : []
  })

  log_router_container = {
    name      = "log_router"
    image     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:3"
    essential = true
    firelensConfiguration = {
      type = "fluentbit"
      options = {
        "enable-ecs-log-metadata" = "true"
      }
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "firelens"
      }
    }
    memoryReservation = 50
  }

  # 同样的类型统一问题:两个分支的列表长度不一样(1 个 vs 2 个 container)，
  # 直接三元表达式会报 tuple 长度不一致。concat() 能正确处理这种情况。
  container_definitions = concat(
    [local.main_container],
    var.enable_firelens ? [local.log_router_container] : []
  )
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn

  container_definitions = jsonencode(local.container_definitions)
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

  dynamic "load_balancer" {
    for_each = var.create_alb ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.this[0].arn
      container_name   = "main"
      container_port   = var.container_port
    }
  }

  health_check_grace_period_seconds = var.create_alb ? 60 : null

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

  depends_on = [aws_lb_listener.http]
}
