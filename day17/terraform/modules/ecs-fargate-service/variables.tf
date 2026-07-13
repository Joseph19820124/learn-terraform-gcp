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
  description = "是否创建公网 ALB。callee 这类纯内部服务应该设为 false。"
  type        = bool
  default     = false
}

variable "enable_service_connect" {
  description = "是否启用 Service Connect(想调用别的 Service Connect 服务，这个必须是 true)"
  type        = bool
  default     = true
}

variable "service_connect_name" {
  description = "这个服务在 Service Connect 里对外暴露的短名字，别的服务用这个名字调用它。留空 = 这个服务不可被按名字发现(比如 caller 自己不需要被别人调用)。"
  type        = string
  default     = ""
}

variable "allowed_security_group_ids" {
  description = "额外允许访问 container_port 的安全组列表(比如 caller 的安全组，用来放行它访问 callee)"
  type        = list(string)
  default     = []
}

variable "docker_labels" {
  description = "写进容器定义的 dockerLabels——day17 用来给 caller 打 Traefik 的路由规则(traefik.enable / traefik.http.routers.*.rule 等)，Traefik 的 ECS provider 靠读这些 label 生成路由，不是靠 ALB 那种显式 target group。"
  type        = map(string)
  default     = {}
}
