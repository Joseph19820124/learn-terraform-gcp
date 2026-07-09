output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "web_url" {
  value = "http://${aws_lb.this.dns_name}/hello"
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_name" {
  value = aws_ecs_service.this.name
}
