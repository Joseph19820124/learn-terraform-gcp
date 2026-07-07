# 从 data source 读到的现有 VPC 信息(证明我们"查到"了它),
# 以及我们自己创建的子网信息。

output "found_existing_vpc_id" {
  description = "data source 查到的现有 VPC 的 ID(注意来自 data.,不是我们建的)"
  value       = data.google_compute_network.existing.id
}

output "created_subnet_name" {
  description = "我们创建并管理的子网"
  value       = google_compute_subnetwork.subnet.name
}
