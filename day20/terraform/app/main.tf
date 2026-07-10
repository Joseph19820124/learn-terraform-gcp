# app/main.tf —— day09 的两服务架构（caller/callee + ECS Service Connect）不变，
# 这一天加的是"同一份配置，部署到 dev/staging/prod 三个环境"。
#
# 环境之间的差异全部来自变量(见 variables.tf + environments/*.tfvars)：
#   - 资源名字前缀(local.full_name)按环境区分，避免 dev/staging/prod 在同一个
#     AWS 账号里互相撞名字。
#   - desired_count / cpu / memory 按环境从小到大递增(dev 最省，prod 最大)。
#   - state 的隔离不在这个文件里 —— 见 backend.tf 的 partial configuration。

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

locals {
  # "day20-dev" / "day20-staging" / "day20-prod" —— 三个环境的所有资源
  # (集群、命名空间、服务、安全组……)都用这个前缀区分，物理上互不干扰。
  full_name = "${var.name}-${var.environment}"
}

module "cluster" {
  source = "../modules/ecs-cluster"
  name   = local.full_name
  vpc_id = data.aws_vpc.default.id
}

# ---------- callee:纯内部服务，没有 ALB，只能被 caller 按 Service Connect 名字调用 ----------
module "callee" {
  source = "../modules/ecs-fargate-service"

  name          = "${local.full_name}-callee"
  region        = var.region
  vpc_id        = data.aws_vpc.default.id
  subnet_ids    = data.aws_subnets.default.ids
  cluster_id    = module.cluster.cluster_id
  namespace_arn = module.cluster.namespace_arn

  container_image = var.callee_image
  create_alb      = false
  cpu             = var.cpu
  memory          = var.memory
  desired_count   = var.desired_count

  service_connect_name       = "callee"
  allowed_security_group_ids = [module.caller.service_security_group_id]
}

# ---------- caller:对外挂 ALB，内部会调用 callee ----------
module "caller" {
  source = "../modules/ecs-fargate-service"

  name          = "${local.full_name}-caller"
  region        = var.region
  vpc_id        = data.aws_vpc.default.id
  subnet_ids    = data.aws_subnets.default.ids
  cluster_id    = module.cluster.cluster_id
  namespace_arn = module.cluster.namespace_arn

  container_image = var.caller_image
  create_alb      = true
  cpu             = var.cpu
  memory          = var.memory
  desired_count   = var.desired_count

  # 注意:下面这个 `environment = { ... }` 是 ecs-fargate-service 模块的入参
  # (注入到容器里的环境变量 map)，和本文件顶部 var.environment(dev/staging/prod
  # 这个部署环境)是两个完全不同的东西，只是恰好同名——这是 Terraform 里常见的
  # "模块参数名"和"根模块变量名"撞名，不是 bug，但读的时候容易搞混。
  environment = {
    CALLEE_URL         = "http://callee:8080"
    DEPLOY_ENVIRONMENT = var.environment
  }
}
