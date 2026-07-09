variable "region" {
  description = "区域"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "资源名字前缀"
  type        = string
  default     = "day08-hello-fargate"
}

variable "container_image" {
  description = "要部署的镜像完整地址(先跑 ../ecr 拿到 repository_url，build+push 镜像后填在这里，带 tag)"
  type        = string
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "autoscale_min" {
  type    = number
  default = 1
}

variable "autoscale_max" {
  type    = number
  default = 3
}
