# outputs.tf —— apply 成功后,把有用的信息打印到终端。
# 以后别的资源(比如 day02 的子网)也会引用这些值。

output "vpc_name" {
  description = "创建出来的 VPC 名字"
  value       = google_compute_network.vpc.name
}

output "vpc_id" {
  description = "VPC 的完整 ID"
  value       = google_compute_network.vpc.id
}

output "vpc_self_link" {
  description = "VPC 的 self_link(在别的资源里引用这个 VPC 时会用到)"
  value       = google_compute_network.vpc.self_link
}
