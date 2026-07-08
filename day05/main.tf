# main.tf(根配置 / root module)—— 调用上面写好的 network 模块。
#
# 核心:同一个模块可以被【调用多次】,每次传不同参数,就得到一套独立的资源。
# 这就是"复用":网络的建法只写一遍(在 modules/network 里),这里用两次。

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

# ---------- 第 1 次调用:建一套 "app" 网络 ----------
module "app_network" {
  source      = "./modules/network" # source = 模块在哪(这里是本地相对路径)
  name        = "app"
  region      = var.region
  subnet_cidr = "10.10.0.0/24"
}

# ---------- 第 2 次调用【同一个模块】:建一套 "data" 网络 ----------
module "data_network" {
  source      = "./modules/network"
  name        = "data"
  region      = var.region
  subnet_cidr = "10.20.0.0/24"
}

# 结果:一份模块代码,建出两套 VPC+子网(app-vpc/app-subnet、data-vpc/data-subnet)。
