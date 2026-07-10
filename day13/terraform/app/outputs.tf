output "caller_url" {
  value = "https://${module.caller.url}"
}

output "callee_url" {
  value = "https://${module.callee.url}"
}
