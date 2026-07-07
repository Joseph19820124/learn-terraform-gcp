# variables.tf —— 把"会变的值"抽成变量,而不是写死在 main.tf 里。
# 这样换项目、换名字时,只改变量就行,不用动主代码。

variable "project_id" {
  description = "你的 GCP 项目 ID(用 `gcloud config get-value project` 可以查到)"
  type        = string
  # 没有 default,所以这是"必填项":不给值 Terraform 会报错提醒你。
}

variable "region" {
  description = "默认区域"
  type        = string
  default     = "us-central1" # 有 default = 选填,不给就用这个
}

variable "vpc_name" {
  description = "要创建的 VPC 名字"
  type        = string
  default     = "my-first-vpc"
}
