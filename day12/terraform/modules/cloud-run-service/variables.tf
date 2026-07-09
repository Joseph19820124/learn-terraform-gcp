variable "name" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "image" {
  type = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "env" {
  type    = map(string)
  default = {}
}

variable "service_account_email" {
  type = string
}

variable "invoker_members" {
  type    = list(string)
  default = []
}

variable "join_mesh" {
  description = "是否给这个 revision 挂 Direct VPC egress + service_mesh block(只有 caller 需要)"
  type        = bool
  default     = false
}

variable "mesh_id" {
  type    = string
  default = ""
}

variable "vpc_network" {
  type    = string
  default = ""
}

variable "vpc_subnetwork" {
  type    = string
  default = ""
}
