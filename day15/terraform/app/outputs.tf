output "caller_web_url" {
  value = module.caller.web_url
}

output "grafana_url" {
  value = module.grafana.base_url
}

output "loki_url" {
  value = module.loki.base_url
}
