variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "name" {
  type    = string
  default = "day11"
}

variable "caller_image" {
  type = string
}

variable "callee_image" {
  type = string
}
