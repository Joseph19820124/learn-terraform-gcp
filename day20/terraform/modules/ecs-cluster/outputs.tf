output "cluster_id" {
  value = aws_ecs_cluster.this.id
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "namespace_arn" {
  value = aws_service_discovery_private_dns_namespace.this.arn
}
