# modules/ecs-fargate-service/main.tf —— 用标准 Terraform AWS provider 资源
# 重构 Nike 案例里 Serverless Framework + 私有插件做的事：
# ECS Fargate service + ALB + Application Auto Scaling。
#
# 和 serverless-original/serverless.yml 的关键区别：
# 那边一份 YAML 背后是插件"黑盒"展开出十几二十个 CloudFormation 资源，你看不到；
# 这里每一个资源都在这份代码里，明明白白写出来、可审查、可 diff。

# ---------- ECS 集群 ----------
# 真实 Nike 案例里集群是共享的、别的团队维护、这里只是 Fn::ImportValue 引用。
# 学习案例为了自包含 + 可 destroy 干净，这里自己建一个。
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = 3 # demo 用途，保留时间设短一点
}

# ---------- IAM:task 执行角色 ----------
# 对应 config.yml 里的 executionRoleArn(真实案例里角色是提前建好、跨栈引用的)。
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

# 这一个托管策略就包含了拉 ECR 镜像 + 写 CloudWatch 日志所需的全部权限，
# 不需要自己再拼一份 IAM policy。
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------- 安全组:ALB 对外，task 只信任 ALB ----------
# 对应 config.yml 里的 alb.securityGroups(真实案例引用现成的安全组)。
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "ALB security group"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # web 入口，预期对外开放
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "service" {
  name        = "${var.name}-service-sg"
  description = "ECS service security group"
  vpc_id      = var.vpc_id

  # 只允许来自 ALB 安全组的流量，不直接对外暴露 —— 和反面教材(day06)里
  # "SSH 对全世界开放"是完全相反的设计:这里 task 对谁都不直接开放，
  # 只信任经过 ALB 的流量。
  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- ALB + Target Group + Listener ----------
# 对应 autoscaling-resources.yml 里的 TargetGroup 资源。
resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false # 学习案例用公网 ALB，方便直接 curl 验证
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
}

resource "aws_lb_target_group" "this" {
  name        = "${var.name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Fargate 用 awsvpc 网络模式，target type 必须是 ip

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
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# ---------- ECS Task Definition + Service ----------
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
        containerPort = var.container_port
        protocol      = "tcp"
      }]
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
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true # 学习案例图简单，没建 NAT gateway，直接给 task 公网 IP 出网拉镜像
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "main"
    container_port   = var.container_port
  }

  # 必须等 listener 建好，ECS service 才能正常注册到 target group
  depends_on = [aws_lb_listener.http]
}

# ---------- Application Auto Scaling ----------
# 对应 autoscaling-resources.yml 里的 ScalableTarget + ScalingPolicy，
# 用的也是同一个底层 AWS 服务(Application Auto Scaling)，只是这里用
# Terraform 原生资源表达，而不是插件生成的 CloudFormation。
resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.autoscale_min
  max_capacity       = var.autoscale_max
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu-target-tracking"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  resource_id        = aws_appautoscaling_target.this.resource_id
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value = var.autoscale_target_cpu

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
