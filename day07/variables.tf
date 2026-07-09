variable "project_id" {
  description = "你的 GCP 项目 ID"
  type        = string
}

variable "region" {
  description = "区域"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "可用区(两台机器这里为简单起见放同一个区)"
  type        = string
  default     = "us-central1-a"
}
