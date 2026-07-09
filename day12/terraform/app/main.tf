# app/main.tf —— 根配置：caller/callee 两个 Cloud Run 服务，通过 Cloud
# Service Mesh 互调(day10 VPC Lattice 的 GCP 对照)。
#
# 和 day11(纯 IAM 互调)的区别:这次引入了真正的 service mesh —— Envoy
# sidecar 自动挂到 caller 上，调用 callee 时不需要应用代码自己去要
# identity token。代价是资源数量暴涨:VPC + 子网、mesh 资源、Private DNS
# zone、Serverless NEG、backend service、HTTPRoute，一共 6 类新资源，
# 这些在 day11 里都不需要。

terraform {
  required_version = ">= 1.10"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.39"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.39"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# service_mesh block(caller 用)是 Beta,只有 google-beta provider 认识它。
provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# ---------- VPC + 子网:caller 用 Direct VPC egress 接进来 ----------
# --mesh 参数要求 Cloud Run revision 先接进一个 VPC(Envoy sidecar 要能连
# 到 mesh 控制面、也要能解析下面建的 Private DNS zone)。不需要额外的
# Serverless VPC Access 连接器 —— Direct VPC egress 直接指定网络/子网即可。
resource "google_compute_network" "this" {
  name                    = "${var.name}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "this" {
  name          = "${var.name}-subnet"
  network       = google_compute_network.this.id
  region        = var.region
  ip_cidr_range = "10.20.0.0/24"

  # 实测踩的坑:第一次 apply 没开这个，caller 的 Envoy sidecar 容器
  # (cloud-run-mesh-proxy)一直卡在 ENVOY_PHASE_SERVER_STATE_PRE_INITIALIZING、
  # 启动探针连续失败 200 次直接超时——根因是 Envoy 要连 mesh 控制面
  # (trafficdirector.googleapis.com 这类 Google API),Direct VPC egress
  # 默认只把去 RFC1918 私网段的流量导进 VPC,去 Google API 的流量走的是
  # VPC 内部路径而不是这个子网本身的出网路径,没开 Private Google Access
  # 就连不通。
  private_ip_google_access = true
}

# ---------- Cloud Service Mesh 的 Mesh 资源 ----------
resource "google_network_services_mesh" "this" {
  name = "${var.name}-mesh"
}

# 提前照着 Google 官方 Terraform 文档自己的示例(它也在 service_mesh 的
# example 里放了一个 time_sleep)加了这个,但第一次 apply 还是失败了——
# 因为这里最初只等了 mesh 本身,漏了等 caller_trafficdirector 这条 IAM
# 绑定的传播延迟(和 day11 踩的那个坑同一类,但这次是 IAM 绑定本身没被
# 显式声明为依赖,不是没等,是根本没等对东西)。实测现象:caller 的 Envoy
# sidecar 容器(cloud-run-mesh-proxy)卡在 ENVOY_PHASE_SERVER_STATE_PRE_INITIALIZING、
# 启动探针连续失败 200 次直接被判定失败。修法:把 IAM 绑定也纳入
# depends_on,并把等待时间从 60s 拉到 90s。
resource "time_sleep" "wait_for_mesh" {
  depends_on      = [google_network_services_mesh.this, google_project_iam_member.caller_trafficdirector]
  create_duration = "90s"
}

# ---------- 服务账号(和 day11 一样，各自专属，caller 的邮箱要提前拿到) ----------
resource "google_service_account" "caller" {
  account_id   = "${var.name}-caller"
  display_name = "day12 caller service account"
}

resource "google_service_account" "callee" {
  account_id   = "${var.name}-callee"
  display_name = "day12 callee service account"
}

# caller 要能读 mesh 的路由配置(Envoy sidecar 通过 xDS 从 mesh 控制面拉
# 配置),需要这个项目级角色。
resource "google_project_iam_member" "caller_trafficdirector" {
  project = var.project_id
  role    = "roles/trafficdirector.client"
  member  = "serviceAccount:${google_service_account.caller.email}"
}

# ---------- callee:普通 Cloud Run 服务，代码和 day11 一样 ----------
# 只允许 caller 的服务账号调用 —— mesh 解决的是"怎么发现/怎么帮你附加
# 凭证",不解决"谁有权限调用",IAM 授权仍然要显式给。
module "callee" {
  source = "../modules/cloud-run-service"

  name                   = "${var.name}-callee"
  project_id             = var.project_id
  region                 = var.region
  image                  = var.callee_image
  service_account_email  = google_service_account.callee.email

  invoker_members = ["serviceAccount:${google_service_account.caller.email}"]
}

# ---------- 把 callee 注册成 mesh 的一个目标:Serverless NEG + backend service ----------
resource "google_compute_region_network_endpoint_group" "callee" {
  name                   = "${var.name}-callee-neg"
  region                 = var.region
  network_endpoint_type  = "SERVERLESS"

  cloud_run {
    service = module.callee.name
  }
}

resource "google_compute_backend_service" "callee" {
  name                   = "${var.name}-callee-backend"
  load_balancing_scheme  = "INTERNAL_SELF_MANAGED"
  protocol               = "HTTP"

  backend {
    group = google_compute_region_network_endpoint_group.callee.id
  }
}

# ---------- Private DNS:给 callee 一个 mesh 内部才能解析的主机名 ----------
# rrdatas 填的是一个占位 IP,从来不会真的被连接到 —— Envoy sidecar 拦截的
# 是"目的地是这个 IP"的流量,查 mesh 控制面拿到真实路由规则,再转发到上面
# 那个 backend service,和 DNS 解析出来的 IP 本身没有关系。
resource "google_dns_managed_zone" "mesh" {
  name        = "${var.name}-mesh-zone"
  dns_name    = "${var.mesh_domain}."
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.this.id
    }
  }
}

resource "google_dns_record_set" "callee" {
  name         = "callee.${var.mesh_domain}."
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.mesh.name
  rrdatas      = ["10.0.0.1"]
}

# ---------- HTTPRoute:把 mesh 内的主机名路由到 callee 的 backend service ----------
resource "google_network_services_http_route" "callee" {
  name       = "${var.name}-callee-route"
  hostnames  = ["callee.${var.mesh_domain}"]
  meshes     = [google_network_services_mesh.this.id]

  rules {
    action {
      destinations {
        service_name = google_compute_backend_service.callee.id
      }
    }
  }
}

# ---------- caller:加入 mesh，调用 callee 用 mesh 内部主机名 ----------
module "caller" {
  source = "../modules/cloud-run-service"

  name                   = "${var.name}-caller"
  project_id             = var.project_id
  region                 = var.region
  image                  = var.caller_image
  service_account_email  = google_service_account.caller.email

  invoker_members = ["allUsers"]

  join_mesh      = true
  mesh_id        = google_network_services_mesh.this.id
  vpc_network    = google_compute_network.this.id
  vpc_subnetwork = google_compute_subnetwork.this.id

  env = {
    CALLEE_URL = "http://callee.${var.mesh_domain}"
  }

  depends_on = [google_network_services_http_route.callee, time_sleep.wait_for_mesh]
}
