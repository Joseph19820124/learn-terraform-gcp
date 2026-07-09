output "service_security_group_id" {
  value = aws_security_group.service.id
}

output "alb_dns_name" {
  value = var.create_alb ? aws_lb.this[0].dns_name : null
}

output "web_url" {
  value = var.create_alb ? "http://${aws_lb.this[0].dns_name}/hello" : null
}

# Lattice 服务的 DNS 名字 —— 调用方拿这个当 URL host 用，
# 注意默认走 80 端口(listener 的默认端口)，不是容器真实监听的 8080。
output "lattice_dns_name" {
  value = var.expose_via_lattice ? aws_vpclattice_service.this[0].dns_entry[0].domain_name : null
}
