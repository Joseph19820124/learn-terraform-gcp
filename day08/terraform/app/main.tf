# app/main.tf —— 根配置:用 default VPC(学习案例图简单，不新建网络)，
# 调用 ecs-fargate-service 模块，部署已经 build+push 好的 Spring Boot 镜像。

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

module "web" {
  source = "../modules/ecs-fargate-service"

  name            = var.name
  region          = var.region
  vpc_id          = data.aws_vpc.default.id
  subnet_ids      = data.aws_subnets.default.ids
  container_image = var.container_image

  desired_count = var.desired_count
  autoscale_min = var.autoscale_min
  autoscale_max = var.autoscale_max
}
