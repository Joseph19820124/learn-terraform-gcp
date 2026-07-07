# main.tf —— 你的第一个 Terraform 配置:在 GCP 上创建一个 VPC 网络
#
# Terraform 世界里最基本的两个概念:
#   1) provider(供应商):告诉 Terraform 你要操作哪个云。这里是 Google Cloud。
#   2) resource(资源):你想创建的具体东西。这里是一个 VPC 网络。
#
# 你只要写清楚"我想要什么"(声明式),Terraform 负责调用 GCP API 把它建出来。

# ---------- 1. 声明要用哪个 provider,并锁定版本(保证换台机器结果一致)----------
terraform {
  required_version = ">= 1.3"

  required_providers {
    google = {
      source  = "hashicorp/google" # 从官方 registry 下载 google provider
      version = "~> 5.0"            # 允许 5.x 的任意小版本
    }
  }
}

# ---------- 2. 配置 provider:用哪个项目、默认哪个区域 ----------
# 认证不写在这里 —— 你在命令行跑过 `gcloud auth application-default login` 后,
# Terraform 会自动用你的身份(详见 README)。
provider "google" {
  project = var.project_id # 用哪个 GCP 项目(来自 variables.tf 的变量)
  region  = var.region
}

# ---------- 3. 真正要创建的资源:一个 VPC 网络 ----------
# 语法:resource "<资源类型>" "<你给它起的本地名字>" { ... }
#   - "google_compute_network" 是资源类型(GCP 的 VPC)
#   - "vpc" 是本地名字,只在这份代码里用来引用它(比如 outputs.tf 里)
resource "google_compute_network" "vpc" {
  name = var.vpc_name

  # false = 自定义模式 VPC:不自动创建子网(子网留到 day02 学)。
  # 若设为 true,GCP 会在每个区域自动帮你各建一个子网。
  auto_create_subnetworks = false
}
