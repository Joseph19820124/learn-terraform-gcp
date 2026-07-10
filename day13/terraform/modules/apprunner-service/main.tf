# modules/apprunner-service/main.tf —— 封装一个 App Runner service，
# caller/callee 各调用一次(和 day07/09/10/11/12 一样的"一份模块调两次"套路)。
#
# 这一天两个服务都是公网可达的(is_publicly_accessible = true)——App
# Runner 没有 Cloud Run 那种 roles/run.invoker 概念，要限制"谁能调用
# callee"只能靠 VPC Ingress Connection(把服务收进特定 VPC)或者应用层
# 自己加认证，为了控制这一天的复杂度没有实现，在 README 里如实记录。

resource "aws_apprunner_service" "this" {
  service_name = var.name

  source_configuration {
    auto_deployments_enabled = false

    image_repository {
      image_identifier      = var.image
      image_repository_type = "ECR"

      image_configuration {
        port                           = tostring(var.container_port)
        runtime_environment_variables  = var.env
      }
    }

    authentication_configuration {
      access_role_arn = var.ecr_access_role_arn
    }
  }

  instance_configuration {
    cpu    = var.cpu
    memory = var.memory
  }

  health_check_configuration {
    protocol = "HTTP"
    path     = "/health"
  }

  auto_scaling_configuration_arn = var.auto_scaling_configuration_arn

  network_configuration {
    ingress_configuration {
      is_publicly_accessible = true
    }
    egress_configuration {
      egress_type = "DEFAULT"
    }
  }
}
