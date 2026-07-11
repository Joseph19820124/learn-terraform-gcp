output "service_security_group_id" {
  value = aws_security_group.service.id
}

output "alb_dns_name" {
  value = var.create_alb ? aws_lb.this[0].dns_name : null
}

output "web_url" {
  value = var.create_alb ? "http://${aws_lb.this[0].dns_name}/hello" : null
}

output "base_url" {
  value = var.create_alb ? "http://${aws_lb.this[0].dns_name}" : null
}

output "service_connect_name" {
  value = var.service_connect_name
}
