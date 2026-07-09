# modules/lattice-network/main.tf —— VPC Lattice 的"服务网络"，
# 相当于 day09 Service Connect 里的 Cloud Map 命名空间，但作用域和能力更大：
# 一个 Service Network 可以跨多个 VPC、甚至跨 AWS 账号关联，
# day09 的 Cloud Map 命名空间只能在单个 VPC 内解析。

resource "aws_vpclattice_service_network" "this" {
  name = var.name
}

# 把 VPC "接入"这个服务网络 —— 接入之后，这个 VPC 里的资源才能解析、
# 访问网络里注册的 Lattice 服务。
resource "aws_vpclattice_service_network_vpc_association" "this" {
  vpc_identifier              = var.vpc_id
  service_network_identifier  = aws_vpclattice_service_network.this.id
}
