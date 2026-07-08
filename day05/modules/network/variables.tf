# 模块的【输入】(接口):调用方通过这些变量把参数传进来。
# 一个设计良好的模块,就是靠 variables(输入)+ outputs(输出)对外提供一个清晰的接口。

variable "name" {
  description = "名字前缀:VPC 叫 <name>-vpc,子网叫 <name>-subnet"
  type        = string
}

variable "region" {
  description = "子网所在区域"
  type        = string
}

variable "subnet_cidr" {
  description = "子网的 IP 段(CIDR)"
  type        = string
}
