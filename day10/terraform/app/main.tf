# app/main.tf —— 根配置：一个 ECS 集群 + VPC Lattice 服务网络 + 两个服务
# (callee 注册进 Lattice；caller 有 ALB，靠 Lattice DNS 名字调用 callee)。

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

# 这次不需要 day09 那种带 Service Connect 命名空间的集群模块 ——
# VPC Lattice 不依赖 ECS 集群层面的任何特殊配置，普通集群就够了。
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
}

module "lattice_network" {
  source = "../modules/lattice-network"
  name   = var.name
  vpc_id = data.aws_vpc.default.id
}

# ---------- callee:注册进 VPC Lattice，没有 ALB ----------
module "callee" {
  source = "../modules/ecs-lattice-service"

  name       = "${var.name}-callee"
  region     = var.region
  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids
  cluster_id = aws_ecs_cluster.this.id

  container_image = var.callee_image
  create_alb      = false

  expose_via_lattice         = true
  lattice_service_network_id = module.lattice_network.service_network_id
}

# ---------- caller:对外挂 ALB，调用 callee 用的是 Lattice DNS 名字 ----------
module "caller" {
  source = "../modules/ecs-lattice-service"

  name       = "${var.name}-caller"
  region     = var.region
  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids
  cluster_id = aws_ecs_cluster.this.id

  container_image = var.caller_image
  create_alb      = true

  # caller 不需要被谁调用，不用注册进 Lattice。
  expose_via_lattice = false

  # 注意:没有端口号！VPC Lattice 的监听器默认走 80(HTTP)，
  # 内部再转发到 callee 容器真实的 8080 端口 —— 这和 day09 直接暴露
  # 容器端口(:8080)的 Service Connect 用法不一样。
  environment = {
    CALLEE_URL = "http://${module.callee.lattice_dns_name}"
  }
}
