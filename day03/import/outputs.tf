# 接管后,这个 VPC 就在 Terraform 的 state 里了,可以像自己建的一样引用它的属性。

output "managed_vpc_id" {
  description = "已接管进 Terraform 管理的 VPC ID"
  value       = google_compute_network.vpc.id
}

output "managed_vpc_name" {
  value = google_compute_network.vpc.name
}
