variable "name" {
  type = string
}

variable "image" {
  description = "ECR 镜像完整地址(含 tag)"
  type        = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "env" {
  type    = map(string)
  default = {}
}

variable "ecr_access_role_arn" {
  description = "App Runner 用来拉取私有 ECR 镜像的 IAM 角色"
  type        = string
}

variable "auto_scaling_configuration_arn" {
  type = string
}

variable "cpu" {
  description = "vCPU 单位:256|512|1024|2048|4096"
  type        = string
  default     = "256"
}

variable "memory" {
  description = "内存 MB:512|1024|2048|3072|4096|..."
  type        = string
  default     = "512"
}
