# modules/cloud-run-service/main.tf —— 封装一个 Cloud Run v2 service +
# (可选)run.invoker 授权列表。caller 和 callee 都调用这个模块，只是参数
# 不同 —— 跟 day07/09/10 一样的"一份模块调两次"套路。
#
# 服务账号特意不在这个模块里创建:callee 的 invoker 绑定需要引用 caller
# 的服务账号邮箱，如果两边服务账号各自建在自己的模块实例里，root 模块
# 没法在创建 callee 之前拿到 caller 的账号邮箱(循环依赖)。所以服务账号
# 提到 root(app/main.tf)去建，这里只接收现成的 email。

resource "google_cloud_run_v2_service" "this" {
  name                = var.name
  location            = var.region
  deletion_protection = false

  # 关键对比点(vs day09/10):这里网络层面其实是 INGRESS_TRAFFIC_ALL，
  # 也就是说 URL 本身是公网可路由的 —— 不像 day09(安全组只放行调用方
  # 安全组 ID)或 day10(安全组只放行 Lattice 托管 prefix list)那样在
  # 网络层就把访问范围锁死。Cloud Run 这边的隔离完全交给下面的 IAM 绑定:
  # 没有 roles/run.invoker 权限的请求，会在流量到达容器之前就被 403 拒绝。
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
  }
}

# 只有传了 invoker_members 才创建 —— caller 传 ["allUsers"](demo 图方便，
# 让人能直接 curl);callee 只传 caller 的服务账号邮箱，别人调不通。
resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = toset(var.invoker_members)

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = each.value
}
