variable "project_id" {
  description = "你的 GCP 项目 ID(用 `gcloud config get-value project` 可查到)"
  type        = string
}

variable "region" {
  description = "区域(子网属于某个区域)"
  type        = string
  default     = "us-central1"
}

variable "vpc_name" {
  description = "VPC 名字"
  type        = string
  default     = "my-first-vpc"
}

variable "subnet_name" {
  description = "子网名字"
  type        = string
  default     = "my-first-subnet"
}

variable "subnet_cidr" {
  description = "子网的 IP 段(CIDR),比如 10.0.0.0/24 可容纳 256 个地址"
  type        = string
  default     = "10.0.0.0/24"
}
