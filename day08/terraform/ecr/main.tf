# ecr/main.tf —— 单独一个小 stack，只管镜像仓库。
#
# 为什么和下面的 app/ 分开:镜像仓库的生命周期和"这次要部署哪个 tag"是两件事——
# 仓库应该长期存在，镜像版本换了不代表仓库要重建。这也是很多团队的真实做法:
# 仓库(及其扫描策略、生命周期规则)一次建好，长期不变;计算层(ECS/K8s)才是
# 频繁变化、跟着 commit 走的部分。

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
  name                 = var.name
  image_tag_mutability = "IMMUTABLE" # 同一个 tag 不能被覆盖推送，保证可追溯

  image_scanning_configuration {
    scan_on_push = true
  }

  # 学习案例用完要 destroy 干净，允许 destroy 时连带清空仓库里的镜像。
  # 生产环境通常不会开这个 —— 镜像仓库不该被 destroy 误删。
  force_delete = true
}
