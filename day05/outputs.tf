# 用 module.<模块实例名>.<输出名> 取模块暴露出来的值。
# app_network / data_network 就是 main.tf 里给两次调用起的名字。

output "app_vpc_name" {
  value = module.app_network.vpc_name
}

output "app_subnet_name" {
  value = module.app_network.subnet_name
}

output "data_vpc_name" {
  value = module.data_network.vpc_name
}

output "data_subnet_name" {
  value = module.data_network.subnet_name
}
