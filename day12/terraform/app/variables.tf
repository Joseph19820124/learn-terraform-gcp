variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "name" {
  type    = string
  default = "day12"
}

variable "mesh_domain" {
  description = "只在 mesh 内部私有 DNS zone 里能解析的假域名"
  type        = string
  default     = "day12.internal"
}

variable "caller_image" {
  type = string
}

variable "callee_image" {
  type = string
}
