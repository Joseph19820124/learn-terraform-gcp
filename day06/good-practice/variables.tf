# 反模式 #2 修正:每个变量都写 description，
# 别人(或未来的你)不用去翻代码就知道这个变量是干嘛的。

variable "project_id" {
  description = "你的 GCP 项目 ID"
  type        = string
}

variable "region" {
  description = "区域"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "VM 所在的可用区"
  type        = string
  default     = "us-central1-a"
}

variable "name" {
  description = "资源名字前缀(VM、防火墙规则都用这个)"
  type        = string
  default     = "day06-web-app"
}

variable "machine_type" {
  description = "机型(e2-micro 是 GCP 里最小最便宜的机型之一，跑一个 nginx 綽綽有余)"
  type        = string
  default     = "e2-micro"
}

variable "ssh_source_ranges" {
  description = <<-EOT
    允许 SSH(22端口)访问的 CIDR 列表。
    【反模式 #4 的核心修正点】：默认是空列表，也就是【默认不开放 SSH】——
    这是"默认最小暴露面"的安全原则。AWS 版那份代码默认对 0.0.0.0/0(全世界)
    开放 22 端口，是明确的反面教材。
    想开 SSH，自己传入你的公网 IP，比如 ["1.2.3.4/32"]，不要传 0.0.0.0/0。
  EOT
  type    = list(string)
  default = []
}
