# main.tf —— day03 / import:把一个【已经存在】的 VPC 接管进 Terraform 管理。
#
# 场景:VPC 是手工建的(或别的工具建的),你想让 Terraform 从此接管它 ——
#      以后由 Terraform 来改它、删它。这叫 import(导入/接管)。

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

# 一个与"现有 VPC"对应的 resource 块。
# 注意:如果【只】写这个块直接 apply,会像 day02 那样报 409(已存在)。
# 关键在下面的 import 块 —— 它告诉 Terraform:不是新建,而是接管这个已存在的。
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

# ---------- import 块(Terraform 1.5+)----------
# to = 接管到哪个 resource 地址;id = 那个真实资源在 GCP 里的 ID。
# apply 时 Terraform 会把这个现有 VPC 纳入 state,而不是创建一个新的。
import {
  to = google_compute_network.vpc
  id = "projects/${var.project_id}/global/networks/${var.vpc_name}"
}
