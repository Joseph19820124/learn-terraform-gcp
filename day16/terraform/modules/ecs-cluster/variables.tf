variable "name" {
  description = "集群/命名空间名字前缀"
  type        = string
}

variable "vpc_id" {
  description = "命名空间要绑定的 VPC(Service Connect 的 DNS 解析范围限定在这个 VPC 内)"
  type        = string
}
