variable "name" {
  description = "服务名字"
  type        = string
}

variable "service_account_email" {
  description = "这个 Cloud Run revision 用哪个服务账号身份运行"
  type        = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "image" {
  description = "容器镜像完整地址(Artifact Registry)"
  type        = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "env" {
  description = "容器环境变量"
  type        = map(string)
  default     = {}
}

variable "invoker_members" {
  description = "有 roles/run.invoker 权限的 member 列表，例如 [\"allUsers\"] 或 [\"serviceAccount:xxx@...\"]；空列表 = 谁都调不通(除了项目 owner/editor)"
  type        = list(string)
  default     = []
}
