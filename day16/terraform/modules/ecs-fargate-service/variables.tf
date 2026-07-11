variable "name" {
  description = "资源名字前缀"
  type        = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "cluster_id" {
  description = "要加入哪个 ECS 集群(来自 ecs-cluster 模块)"
  type        = string
}

variable "namespace_arn" {
  description = "Service Connect 命名空间 ARN(来自 ecs-cluster 模块)"
  type        = string
}

variable "container_image" {
  type = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "container_port_name" {
  description = "Service Connect 用来引用端口的名字(要和 client_alias 对应)"
  type        = string
  default     = "http"
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "cpu" {
  type    = number
  default = 256
}

variable "memory" {
  type    = number
  default = 512
}

variable "desired_count" {
  type    = number
  default = 1
}

variable "environment" {
  description = "注入到容器的环境变量"
  type        = map(string)
  default     = {}
}

variable "create_alb" {
  type    = bool
  default = false
}

variable "enable_service_connect" {
  type    = bool
  default = true
}

variable "service_connect_name" {
  type    = string
  default = ""
}

variable "allowed_security_group_ids" {
  type    = list(string)
  default = []
}

# ---------- 这一天新加的:FireLens/Loki 相关 ----------
variable "enable_firelens" {
  description = "开启后:主容器日志走 awsfirelens + log_router sidecar 转发到 Loki,而不是 CloudWatch"
  type        = bool
  default     = false
}

variable "loki_host" {
  description = "Loki 的 Service Connect 短名字或地址(仅 enable_firelens=true 时用到)"
  type        = string
  default     = "loki"
}

variable "loki_port" {
  type    = number
  default = 3100
}
