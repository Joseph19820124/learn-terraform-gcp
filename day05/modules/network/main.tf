# modules/network/main.tf —— 一个可复用的"网络"模块:建 VPC + 子网。
#
# 注意:模块里【不写】provider、terraform{} backend 这些块 ——
# 子模块会自动继承根配置(调用它的那个)的 provider。模块只专注"要建什么资源"。

resource "google_compute_network" "vpc" {
  name                    = "${var.name}-vpc" # 名字用传进来的前缀拼,保证每次调用不重名
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
}
