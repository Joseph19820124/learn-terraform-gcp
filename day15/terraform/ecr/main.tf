# registry/main.tf —— caller/callee/grafana 需要自己的镜像仓库(grafana
# 要把 Loki 数据源"烤"进镜像,不能直接用官方镜像)。Loki 本身和 FireLens
# 的 log_router sidecar 都用公共镜像(grafana/loki、aws-for-fluent-bit)，
# 不需要 ECR。

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

resource "aws_ecr_repository" "this" {
  for_each = toset(["caller", "callee", "grafana"])

  name                 = "${var.name}-${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  force_delete = true
}
