# main.tf —— day06:功能对等于"AWS EC2 + httpd" demo 的 GCP 版本，
# 但修掉了那份代码里的 5 个反模式(见 ../README.md 逐条对照)。

terraform {
  # 反模式 #5 修正:锁定 Terraform 和 provider 版本，
  # 不会因为 provider 出 breaking change 而突然跑不动。
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

# 反模式 #1 修正:不写死 image ID，而是用 data source 查"当前最新"的镜像。
# AWS 版写死了一个 2025 年的 AMI，现在已经 deprecated。
# 这里用 image family(镜像家族)代替具体版本号，Google 会自动解析到该家族
# 当前最新、未废弃的版本 —— 以后重新 apply 永远拿到能用的镜像，不会腐坏。
data "google_compute_image" "web" {
  family  = "debian-12"
  project = "debian-cloud"
}

# ---------- 防火墙:分成两条规则，而不是一条"全开放" ----------
# 反模式 #4 修正(核心差异):AWS 版把 22(SSH) 和 80(HTTP) 一起对 0.0.0.0/0 开放。
# HTTP 对全世界开放是 web 服务器的正常预期行为，但 SSH 对全世界开放是真正的风险。
# 这里把两者拆开，SSH 默认不开放(见 variables.tf 的 ssh_source_ranges 默认值)。

resource "google_compute_firewall" "allow_http" {
  name    = "${var.name}-allow-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"] # web 服务器本来就要给所有人访问，这是预期暴露
  target_tags   = [var.name]
}

resource "google_compute_firewall" "allow_ssh" {
  # 只有 var.ssh_source_ranges 非空时才创建这条规则(见 variables.tf)。
  # 默认是空列表 = 默认不开 SSH，你必须显式传入你自己的 IP 才能开。
  count   = length(var.ssh_source_ranges) > 0 ? 1 : 0
  name    = "${var.name}-allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges # 默认最小暴露面，不是 0.0.0.0/0
  target_tags   = [var.name]
}

# ---------- VM 实例 ----------
resource "google_compute_instance" "web" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = [var.name] # 给上面的防火墙规则用 target_tags 匹配

  boot_disk {
    initialize_params {
      image = data.google_compute_image.web.self_link
    }
  }

  network_interface {
    network = "default"
    access_config {} # 空块 = 分配一个临时公网 IP
  }

  # 等价于 AWS 版的 user_data：开机脚本，装 nginx 并起一个首页。
  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    echo "<h1>Welcome to the Terraform Web App (GCP edition)</h1>" > /var/www/html/index.html
    systemctl enable nginx
    systemctl start nginx
  EOT
}
