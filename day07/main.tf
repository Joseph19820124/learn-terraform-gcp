# main.tf(根配置)—— 调用 secure-web-server 模块两次，
# 证明"安全基线只写一遍，调用 N 次都自动带上"。

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

# ---------- 调用 1:team-a 的 web 服务器 ----------
module "team_a_web" {
  source = "./modules/secure-web-server"
  name   = "day07-team-a-web"
  zone   = var.zone
  message = "Hello from Team A! (deployed via the secure-web-server module)"
  # 没传 ssh_source_ranges —— 继承模块默认值:不开放 SSH。
}

# ---------- 调用 2:team-b 的 web 服务器 ----------
module "team_b_web" {
  source = "./modules/secure-web-server"
  name   = "day07-team-b-web"
  zone   = var.zone
  message = "Hello from Team B! (same module, same security baseline)"
}

# 结果:两台机器、两个团队各自的首页，但"镜像动态解析 / SSH 默认关闭 /
# HTTP 按预期开放"这套安全基线，两边完全一致 —— 因为它们用的是同一份模块代码。
