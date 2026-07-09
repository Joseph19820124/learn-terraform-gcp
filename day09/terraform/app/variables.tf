variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "day09"
}

variable "caller_image" {
  description = "caller 服务的完整镜像地址(含 tag)"
  type        = string
}

variable "callee_image" {
  description = "callee 服务的完整镜像地址(含 tag)"
  type        = string
}
