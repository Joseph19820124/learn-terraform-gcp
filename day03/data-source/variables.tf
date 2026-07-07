variable "project_id" {
  description = "你的 GCP 项目 ID"
  type        = string
}

variable "region" {
  description = "区域"
  type        = string
  default     = "us-central1"
}

variable "existing_vpc_name" {
  description = "一个【已经存在】的 VPC 名字(data source 会去查它)"
  type        = string
  default     = "day03-existing-vpc"
}

variable "subnet_name" {
  description = "要在现有 VPC 里创建的子网名字"
  type        = string
  default     = "day03-ds-subnet"
}

variable "subnet_cidr" {
  description = "子网 IP 段"
  type        = string
  default     = "10.3.0.0/24"
}
