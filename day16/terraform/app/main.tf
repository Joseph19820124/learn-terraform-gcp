# app/main.tf —— 根配置：day09 的 caller/callee 加上 Loki + Grafana。
# caller/callee 开 FireLens,日志转发到 loki;grafana 预配置好 Loki 数据源。
# 为了验证方便,loki 和 grafana 这两天都挂了公网 ALB(生产环境里 Loki
# 通常不会直接公开,这里纯粹是为了能直接 curl 验证,不是安全建议)。

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

# ---------- callee:和 day09 一样纯内部,唯一区别是开了 FireLens ----------
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

  service_connect_name       = "callee"
  allowed_security_group_ids = [module.caller.service_security_group_id]

  enable_firelens = true
}

# ---------- caller:和 day09 一样有公网 ALB,唯一区别是开了 FireLens ----------
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

  environment = {
    CALLEE_URL = "http://callee:8080"
  }

  enable_firelens = true
}

# ---------- grafana:公网 ALB,预配置好 Loki 数据源,靠 Service Connect 解析 "loki" ----------
module "grafana" {
  source = "../modules/ecs-fargate-service"

  name          = "${var.name}-grafana"
  region        = var.region
  vpc_id        = data.aws_vpc.default.id
  subnet_ids    = data.aws_subnets.default.ids
  cluster_id    = module.cluster.cluster_id
  namespace_arn = module.cluster.namespace_arn

  container_image   = var.grafana_image
  container_port    = 3000
  health_check_path = "/api/health"
  create_alb        = true

  # 匿名 Viewer + 已知的 admin 密码:图教学方便,不是生产安全建议。
  environment = {
    GF_SECURITY_ADMIN_USER     = "admin"
    GF_SECURITY_ADMIN_PASSWORD = "day16admin"
    GF_AUTH_ANONYMOUS_ENABLED  = "true"
    GF_AUTH_ANONYMOUS_ORG_ROLE = "Viewer"
  }
}

# ---------- loki:接收 caller/callee 的日志,也接 grafana 的查询 ----------
# 额外挂了公网 ALB 纯粹是为了验证方便(直接 curl /loki/api/v1/query_range
# 看日志进没进来),不需要经过 Grafana 的鉴权。真实生产场景通常不会这样开。
module "loki" {
  source = "../modules/ecs-fargate-service"

  name          = "${var.name}-loki"
  region        = var.region
  vpc_id        = data.aws_vpc.default.id
  subnet_ids    = data.aws_subnets.default.ids
  cluster_id    = module.cluster.cluster_id
  namespace_arn = module.cluster.namespace_arn

  container_image   = "grafana/loki:3.3.2"
  container_port    = 3100
  health_check_path = "/ready"
  create_alb        = true

  service_connect_name = "loki"
  allowed_security_group_ids = [
    module.caller.service_security_group_id,
    module.callee.service_security_group_id,
    module.grafana.service_security_group_id,
  ]
}
