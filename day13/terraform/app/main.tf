# app/main.tf —— 根配置:两个 App Runner 服务(caller/callee)。
#
# 2026-04-30 起 App Runner 已停止对"新客户"开放(现有客户不受影响、
# 能继续新建资源)。aws-10 这个账号此前从没用过 App Runner —— 这一天
# 本身就是在实测"这个账号到底还算不算能用",不是假设它一定能用。

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

# App Runner 拉取私有 ECR 镜像需要一个专门的 IAM 角色(区别于 ECS 的
# execution role)，信任的 principal 是 build.apprunner.amazonaws.com。
data "aws_iam_policy_document" "apprunner_ecr_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["build.apprunner.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apprunner_ecr_access" {
  name               = "${var.name}-apprunner-ecr-access"
  assume_role_policy = data.aws_iam_policy_document.apprunner_ecr_trust.json
}

resource "aws_iam_role_policy_attachment" "apprunner_ecr_access" {
  role       = aws_iam_role.apprunner_ecr_access.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSAppRunnerServicePolicyForECRAccess"
}

# 两个服务共用一份 auto scaling 配置。App Runner 不支持缩到 0——
# min_size 至少是 1，意味着哪怕没有请求也会一直有实例在跑、一直计费，
# 这一点和 Cloud Run(day11/12)、甚至 ECS+ALB(day09/10,虽然也不缩到0
# 但至少概念上一致)都不一样，是这一天要验证的另一个真实差异点。
resource "aws_apprunner_auto_scaling_configuration_version" "this" {
  auto_scaling_configuration_name = var.name

  min_size        = 1
  max_size        = 2
  max_concurrency = 50
}

# ---------- callee:公网可达,没有任何调用方限制 ----------
module "callee" {
  source = "../modules/apprunner-service"

  name                            = "${var.name}-callee"
  image                           = var.callee_image
  ecr_access_role_arn             = aws_iam_role.apprunner_ecr_access.arn
  auto_scaling_configuration_arn  = aws_apprunner_auto_scaling_configuration_version.this.arn
}

# ---------- caller:同样公网可达,调用 callee 用它的默认域名 ----------
module "caller" {
  source = "../modules/apprunner-service"

  name                            = "${var.name}-caller"
  image                           = var.caller_image
  ecr_access_role_arn             = aws_iam_role.apprunner_ecr_access.arn
  auto_scaling_configuration_arn  = aws_apprunner_auto_scaling_configuration_version.this.arn

  env = {
    CALLEE_URL = "https://${module.callee.url}"
  }
}
