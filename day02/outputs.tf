# apply 后打印 VPC 和子网的关键信息。
# 注意 outputs 也是通过"引用"资源属性拿到值的。

output "vpc_name" {
  description = "VPC 名字"
  value       = google_compute_network.vpc.name
}

output "subnet_name" {
  description = "子网名字"
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_cidr" {
  description = "子网的 IP 段"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}

output "subnet_region" {
  description = "子网所在区域"
  value       = google_compute_subnetwork.subnet.region
}

output "subnet_gateway_ip" {
  description = "GCP 自动分配的子网网关地址(第一个可用 IP)"
  value       = google_compute_subnetwork.subnet.gateway_address
}
