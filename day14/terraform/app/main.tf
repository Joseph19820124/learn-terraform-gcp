# app/main.tf —— 根配置：两个 ECS Express Mode 服务(caller/callee)。
# 这一天刻意和 day13(App Runner)保持对等范围：两个服务都用默认公网
# 子网,不做私有子网+内部 ALB 的隔离实验(那个留作已知可选项写进 README，
# 不在这一天实现——用户明确选的是"简单版，和 day13 对等")。

terraform {
  required_version = ">= 1.10"
  required_providers {
    # ECS Express Mode(aws_ecs_express_gateway_service)是 2025-11 才发布的
    # 新功能,day08-13 一直用的 ~> 5.0 里没有这个资源类型 —— 实测踩过一次
    # "Invalid resource type" 才发现要用 6.x。这一天单独锁 6.x,不动其它
    # 天的 provider 版本。
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ---------- execution role:和 day08-10 完全一样的标准 ECS execution role ----------
data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------- infrastructure role:Express Mode 专属,day08-10 完全没有这个东西 ----------
# ECS 要替你自动建 ALB/target group/安全组/auto scaling 这一整套，需要一个
# 专门的角色，信任的 principal 是 ecs.amazonaws.com(不是 ecs-tasks.amazonaws.com)。
data "aws_iam_policy_document" "ecs_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "infrastructure" {
  name               = "${var.name}-infra"
  assume_role_policy = data.aws_iam_policy_document.ecs_trust.json
}

resource "aws_iam_role_policy_attachment" "infrastructure" {
  role       = aws_iam_role.infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}

# 实测踩的坑:一开始直接给 aws_ecs_express_gateway_service 传了
# cluster = var.name,以为和 App Runner 一样"给个名字就自动建"——实际
# 报错 "ClusterNotFoundException"。文档原话是"The ECS default cluster
# (if it does not already exist)"会自动建,但那是指字面意义上的
# default 集群,自定义名字的集群必须自己先建好。这里显式建一个,和
# day08-10 一贯的做法(不共用 AWS 账号全局的 default 集群)保持一致。
resource "aws_ecs_cluster" "this" {
  name = var.name
}

# ---------- callee:先建出来,caller 需要引用它的默认域名 ----------
resource "aws_ecs_express_gateway_service" "callee" {
  service_name             = "${var.name}-callee"
  cluster                  = aws_ecs_cluster.this.name
  execution_role_arn       = aws_iam_role.execution.arn
  infrastructure_role_arn  = aws_iam_role.infrastructure.arn
  health_check_path        = "/health"

  primary_container {
    image          = var.callee_image
    container_port = 8080
  }
}

# ---------- caller:调用 callee 用 Express Mode 自动分配的默认域名 ----------
resource "aws_ecs_express_gateway_service" "caller" {
  service_name             = "${var.name}-caller"
  cluster                  = aws_ecs_cluster.this.name
  execution_role_arn       = aws_iam_role.execution.arn
  infrastructure_role_arn  = aws_iam_role.infrastructure.arn
  health_check_path        = "/health"

  primary_container {
    image          = var.caller_image
    container_port = 8080

    environment {
      name  = "CALLEE_URL"
      # 实测踩的坑:ingress_paths[0].endpoint 本身就已经带 https:// 前缀了，
      # 一开始按其它天"endpoint 只是裸域名"的习惯加了一层 https:// 拼接，
      # 结果输出变成 https://https://...，caller 运行时请求会直接失败。
      value = aws_ecs_express_gateway_service.callee.ingress_paths[0].endpoint
    }
  }

  depends_on = [aws_ecs_express_gateway_service.callee]
}
