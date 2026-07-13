# 唯一的公网入口不再是 caller 自己的 ALB，而是 Traefik 前面的 ALB——
# 但这个 ALB 只做入口/健康检查，不写死任何路由规则；真正"该转发给谁"
# 这个决策，全靠 Traefik 读 caller 的 dockerLabels 动态生成。
output "traefik_url" {
  value = "http://${aws_lb.traefik.dns_name}/hello"
}

# caller 自己应该没有 ALB 了(create_alb=false)——这一天想证明的事情之一：
# 路由决策这一层完全从"写死的 target group"挪到了 Traefik 的动态发现。
output "caller_has_no_own_alb" {
  value = module.caller.alb_dns_name == null ? "caller 没有自己的 ALB(符合设计,入口在 Traefik)" : "⚠️ 不对，caller 不应该再有自己的 ALB"
}

# callee 没有 ALB，也不在 Traefik 的路由规则里(没打 traefik.enable 标签)，
# 从公网访问不到——和 day09 一样的结论，这一天没变。
output "callee_has_no_public_url" {
  value = module.callee.alb_dns_name == null ? "callee 没有公网入口(符合设计)" : "⚠️ 不对，callee 不应该有 ALB"
}
