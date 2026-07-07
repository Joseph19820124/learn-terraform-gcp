# main.tf —— day04:代码本身很简单(还是建一个 VPC),
# 重点在 backend.tf:这次 state 存到了 GCS,而不是本地。

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

# 一个普通的 VPC。你 apply 之后会发现:本地【没有】terraform.tfstate 文件了 ——
# 因为 state 被存到了 GCS 桶里(backend.tf 配置的那个)。
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}
