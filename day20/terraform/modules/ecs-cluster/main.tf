# modules/ecs-cluster/main.tf —— 两个服务共享的集群 + Service Connect 命名空间。
#
# ECS Service Connect 靠一个 Cloud Map 私有 DNS 命名空间打通服务发现，
# 绑定在集群的 service_connect_defaults 上，这样每个 service 不用重复声明。

resource "aws_service_discovery_private_dns_namespace" "this" {
  name = "${var.name}.local"
  vpc  = var.vpc_id
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"

  service_connect_defaults {
    namespace = aws_service_discovery_private_dns_namespace.this.arn
  }
}
