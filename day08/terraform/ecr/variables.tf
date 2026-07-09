variable "region" {
  description = "区域"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "ECR 仓库名"
  type        = string
  default     = "day08-hello-fargate"
}
