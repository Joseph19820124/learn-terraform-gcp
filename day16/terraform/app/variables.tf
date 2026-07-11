variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "day16"
}

variable "caller_image" {
  type = string
}

variable "callee_image" {
  type = string
}

variable "grafana_image" {
  type = string
}
