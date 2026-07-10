variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  type    = string
  default = "day20"
}

variable "environment" {
  description = "部署到哪个环境:dev / staging / prod。会拼进所有资源名字，避免三个环境互相撞名字；也决定用哪份 backend-configs/*.hcl(state 隔离)。"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment 必须是 dev、staging 或 prod 之一。"
  }
}

variable "caller_image" {
  description = "caller 服务的完整镜像地址(含 tag)。三个环境通常填同一个 tag —— 这就是\"同一个镜像逐环境晋升\"的部署方式，而不是每个环境单独 build。"
  type        = string
}

variable "callee_image" {
  description = "callee 服务的完整镜像地址(含 tag)"
  type        = string
}

variable "desired_count" {
  description = "caller/callee 各自的期望任务数。建议 dev=1、staging=2、prod=3，在对应的 environments/*.tfvars 里设置。"
  type        = number
  default     = 1
}

variable "cpu" {
  description = "每个任务的 CPU(Fargate 单位:256/512/1024...)，按环境在 environments/*.tfvars 里调整。"
  type        = number
  default     = 256
}

variable "memory" {
  description = "每个任务的内存(MB)，按环境在 environments/*.tfvars 里调整。"
  type        = number
  default     = 512
}
