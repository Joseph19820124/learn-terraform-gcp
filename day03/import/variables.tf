variable "project_id" {
  description = "你的 GCP 项目 ID"
  type        = string
}

variable "region" {
  description = "区域"
  type        = string
  default     = "us-central1"
}

variable "vpc_name" {
  description = "要接管(import)的现有 VPC 名字"
  type        = string
  default     = "day03-import-vpc"
}
