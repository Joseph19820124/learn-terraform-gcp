# modules/cloud-run-service/main.tf —— day11 同款模块，加了一个可选的
# "加入 mesh" 开关。callee 完全不用碰这个开关(就是个普通 Cloud Run 服务)；
# caller 传 join_mesh=true，模块会给它挂上 vpc_access(Direct VPC egress，
# --mesh 参数要求先接进 VPC)和 service_mesh 两个 block。
#
# service_mesh 这个 block 目前是 Beta:Google 官方文档的示例里明确写着
# `provider = google-beta`、`launch_stage = "BETA"`——用默认的 google
# provider 直接写这个 block 会报 "Unsupported block type"(本 day 实测踩过
# 一次,查文档确认后改成 google-beta 就好了)。

terraform {
  required_providers {
    google-beta = {
      source = "hashicorp/google-beta"
    }
  }
}

resource "google_cloud_run_v2_service" "this" {
  provider = google-beta

  name                = var.name
  location            = var.region
  deletion_protection = false
  launch_stage        = var.join_mesh ? "BETA" : null

  ingress = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = var.service_account_email

    containers {
      image = var.image

      ports {
        container_port = var.container_port
      }

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }
    }

    # 只有 caller(join_mesh=true)才需要:Direct VPC egress，把这个
    # revision 接进指定的 VPC/子网 —— --mesh 参数依赖这个,因为 Envoy
    # sidecar 要能访问 mesh 控制面、也要能解析我们建的 Private DNS zone。
    dynamic "vpc_access" {
      for_each = var.join_mesh ? [1] : []
      content {
        network_interfaces {
          network    = var.vpc_network
          subnetwork = var.vpc_subnetwork
        }
      }
    }

    # 只有 caller 才有这个 block:声明这个 revision 加入哪个 Cloud Service
    # Mesh。挂了这个之后,Cloud Run 平台会自动给它注入一个 Envoy sidecar，
    # 拦截容器发出的流量，按 mesh 的 HTTPRoute 规则做服务发现/路由/鉴权。
    dynamic "service_mesh" {
      for_each = var.join_mesh ? [1] : []
      content {
        mesh = var.mesh_id
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  provider = google-beta
  for_each = toset(var.invoker_members)

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = each.value
}
