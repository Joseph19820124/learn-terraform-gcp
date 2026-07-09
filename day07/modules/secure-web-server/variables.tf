# 模块的输入接口。刻意只暴露"调用方真正需要关心"的旋钮——
# 镜像家族、机型这些给了安全默认值；SSH 默认关闭；version 锁定不在这里
# (由根配置的 required_providers 统一管，模块不重复声明)。

variable "name" {
  description = "资源名字前缀(实例名、防火墙规则名都用它，必须在项目内唯一)"
  type        = string
}

variable "zone" {
  description = "部署到哪个可用区"
  type        = string
}

variable "machine_type" {
  description = "机型"
  type        = string
  default     = "e2-micro"
}

variable "image_family" {
  description = "镜像家族(不是具体版本号，Google 会解析到该家族当前最新可用版本)"
  type        = string
  default     = "debian-12"
}

variable "image_project" {
  description = "镜像所在的项目(公共镜像通常在 debian-cloud / ubuntu-os-cloud 这类项目下)"
  type        = string
  default     = "debian-cloud"
}

variable "message" {
  description = "首页要显示的一句话"
  type        = string
  default     = "Hello from a reusable secure-baseline web server module!"
}

variable "ssh_source_ranges" {
  description = "允许 SSH 的 CIDR 列表。默认空 = 默认不开放 SSH(安全基线的核心)。"
  type        = list(string)
  default     = []
}
