# app/main.tf —— 根配置：一个共享集群 + 两个服务(caller 有 ALB，callee 没有)，
# 靠 ECS Service Connect 让 caller 按名字("callee")调用 callee。

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

# ---------- caller:对外挂 ALB，内部会调用 callee ----------
module "caller" {
  source = "../modules/ecs-fargate-service"

  name          = "${var.name}-caller"
  region        = var.region
  vpc_id        = data.aws_vpc.default.id
  subnet_ids    = data.aws_subnets.default.ids
  cluster_id    = module.cluster.cluster_id
  namespace_arn = module.cluster.namespace_arn

  container_image = var.caller_image
  create_alb      = true

  # caller 不需要被别人按名字调用，所以 service_connect_name 留空；
  # 但 enable_service_connect 默认是 true，这样它才能"发起"对 callee 的调用。
  environment = {
    CALLEE_URL = "http://callee:8080"
  }
}
