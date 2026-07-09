output "caller_web_url" {
  value = module.caller.web_url
}

# callee 没有 ALB，所以没有公网 URL —— 这本身就是想证明的事情：
# 它存在、能被 caller 调用，但从公网访问不到。
output "callee_has_no_public_url" {
  value = module.callee.alb_dns_name == null ? "callee 没有公网入口(符合设计)" : "⚠️ 不对，callee 不应该有 ALB"
}
