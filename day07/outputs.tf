# module.<调用时起的名字>.<模块的输出名> —— day05 学过的取值语法。

output "team_a_url" {
  value = module.team_a_web.web_url
}

output "team_b_url" {
  value = module.team_b_web.web_url
}
