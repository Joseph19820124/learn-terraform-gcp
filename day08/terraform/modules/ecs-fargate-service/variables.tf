variable "name" {
  description = "资源名字前缀"
  type        = string
}

variable "region" {
  description = "部署区域(CloudWatch 日志配置需要)"
  type        = string
}

variable "vpc_id" {
  description = "部署到哪个 VPC"
  type        = string
}

variable "subnet_ids" {
  description = "至少 2 个不同可用区的子网 ID(ALB 要求)"
  type        = list(string)
}

variable "container_image" {
  description = "容器镜像完整地址，含 tag(比如 ECR 仓库 URL:tag)"
  type        = string
}

variable "container_port" {
  description = "容器监听的端口"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "ALB 健康检查路径"
  type        = string
  default     = "/health"
}

variable "cpu" {
  description = "Fargate task 的 CPU(单位:vCPU 的 1/1024，256=0.25 vCPU)"
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task 的内存(MB)"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "期望运行的 task 数"
  type        = number
  default     = 1
}

variable "autoscale_min" {
  description = "自动扩缩容最小 task 数"
  type        = number
  default     = 1
}

variable "autoscale_max" {
  description = "自动扩缩容最大 task 数"
  type        = number
  default     = 3
}

variable "autoscale_target_cpu" {
  description = "目标追踪扩缩容的 CPU 利用率(%)"
  type        = number
  default     = 50
}
