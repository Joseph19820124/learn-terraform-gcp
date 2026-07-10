output "url" {
  description = "App Runner 分配的默认域名(不带协议前缀,一律用 https)"
  value       = aws_apprunner_service.this.service_url
}

output "arn" {
  value = aws_apprunner_service.this.arn
}
