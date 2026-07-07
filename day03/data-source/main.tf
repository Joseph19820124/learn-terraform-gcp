# main.tf —— day03 / data source:引用一个【已经存在】的 VPC,并在里面建子网。
#
# 场景:VPC 是"别人建好的"(比如网络团队,或你手工用 gcloud 建的),
#      你不想、也不该去创建或删除它 —— 你只想"用上它"。
# 这时用 data source:Terraform 只【查/读】它,永远不会创建/改/删它。

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

# ---------- data source:查找一个已存在的 VPC(只读,不管理它)----------
# 注意关键字是 data,不是 resource。Terraform 会去 GCP 按名字把它查出来。
data "google_compute_network" "existing" {
  name = var.existing_vpc_name
}

# ---------- resource:我们真正创建/管理的,只有这个子网 ----------
resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region

  # ★ 引用的是 data.(数据源),不是 resource。
  #   意思:把子网挂到"那个查出来的现有 VPC"上。
  network = data.google_compute_network.existing.id
}
