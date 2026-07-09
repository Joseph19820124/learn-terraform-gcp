variable "name" {
  description = "服务网络名字"
  type        = string
}

variable "vpc_id" {
  description = "要接入这个服务网络的 VPC"
  type        = string
}
