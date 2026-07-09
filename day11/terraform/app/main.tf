# app/main.tf —— 根配置：两个 Cloud Run 服务(caller/callee)，靠 IAM 互调，
# 不需要任何 service mesh、不需要 VPC、不需要安全组。

terraform {
  required_version = ">= 1.10"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.39"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# 各自专属的服务账号，用来在 IAM 层面区分"谁在调用" —— 对应 day09/10 里
# "每个服务一个安全组"的角色，只是这次隔离发生在 IAM 而不是网络层。
resource "google_service_account" "caller" {
  account_id   = "${var.name}-caller"
  display_name = "day11 caller service account"
}

resource "google_service_account" "callee" {
  account_id   = "${var.name}-callee"
  display_name = "day11 callee service account"
}

# ---------- callee:只允许 caller 的服务账号调用 ----------
module "callee" {
  source = "../modules/cloud-run-service"

  name                   = "${var.name}-callee"
  project_id             = var.project_id
  region                 = var.region
  image                  = var.callee_image
  service_account_email  = google_service_account.callee.email

  # 关键点:这里没有引用 caller 的安全组 ID(day09)也没有引用 prefix
  # list(day10)——直接写 caller 的服务账号身份。没有这个身份、或者身份
  # 对但没有 run.invoker 权限的请求，Cloud Run 平台会在流量到达容器前
  # 直接 403，容器代码完全不用做鉴权判断。
  invoker_members = ["serviceAccount:${google_service_account.caller.email}"]
}

# ---------- caller:允许 allUsers 调用，方便直接 curl 验证 ----------
module "caller" {
  source = "../modules/cloud-run-service"

  name                   = "${var.name}-caller"
  project_id             = var.project_id
  region                 = var.region
  image                  = var.caller_image
  service_account_email  = google_service_account.caller.email

  invoker_members = ["allUsers"]

  env = {
    CALLEE_URL = module.callee.url
  }
}
