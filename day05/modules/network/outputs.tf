# 模块的【输出】(接口):把内部资源的有用属性暴露给调用方。
# 调用方用 module.<模块实例名>.<输出名> 来取这些值(见根目录的 outputs.tf)。

output "vpc_id" {
  value = google_compute_network.vpc.id
}

output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "subnet_id" {
  value = google_compute_subnetwork.subnet.id
}

output "subnet_name" {
  value = google_compute_subnetwork.subnet.name
}
