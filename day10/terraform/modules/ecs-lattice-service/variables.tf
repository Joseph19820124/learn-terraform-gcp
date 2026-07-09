variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "cluster_id" {
  type = string
}

variable "container_image" {
  type = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "container_port_name" {
  type    = string
  default = "http"
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "environment" {
  type    = map(string)
  default = {}
}

variable "create_alb" {
  description = "是否创建公网 ALB"
  type        = bool
  default     = false
}

variable "expose_via_lattice" {
  description = "是否把这个服务注册进 VPC Lattice，让别的服务能发现它"
  type        = bool
  default     = false
}

variable "lattice_service_network_id" {
  description = "要接入的 VPC Lattice 服务网络 ID(expose_via_lattice=true 时必填)"
  type        = string
  default     = ""
}
