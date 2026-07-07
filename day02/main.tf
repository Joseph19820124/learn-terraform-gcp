# main.tf —— day02:在 VPC 里创建一个子网(subnet)
#
# 今天的新知识点:【资源之间的引用】。
# 子网必须属于某个 VPC,我们会让子网"引用" day01 学的那个 VPC 资源。
# Terraform 看到这个引用,就自动知道:要先建 VPC,再建子网(依赖顺序)。

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

# ---------- 资源 1:VPC 网络(和 day01 一样)----------
resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false # 关掉自动子网,因为我们要自己手动建一个
}

# ---------- 资源 2:子网,建在上面那个 VPC 里 ----------
resource "google_compute_subnetwork" "subnet" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr # 这个子网的 IP 段,比如 10.0.0.0/24
  region        = var.region      # 子网是【区域级】资源,必须指定 region

  # ★ 关键:引用上面的 VPC。
  #   写法是 <资源类型>.<本地名>.<属性> —— 这里取 VPC 的 id。
  #   正因为这一行,Terraform 才知道"子网依赖 VPC",会先建 VPC 再建子网;
  #   destroy 时反过来,先删子网再删 VPC。这叫【隐式依赖】,不用手写顺序。
  network = google_compute_network.vpc.id
}
