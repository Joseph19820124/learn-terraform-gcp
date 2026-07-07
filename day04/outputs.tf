output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "note" {
  description = "提醒:这次的 state 不在本地,而在 backend.tf 配置的 GCS 桶里"
  value       = "state 存在 GCS,不是本地 terraform.tfstate —— 用 `gcloud storage ls` 去桶里看"
}
