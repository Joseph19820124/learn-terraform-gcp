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
  description = "VPC 名字"
  type        = string
  default     = "day04-vpc"
}
