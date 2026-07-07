# Day 02 — 在 VPC 里加一个子网(subnet):学会资源之间的引用

目标:在一个 VPC 里创建 **子网**,并理解 Terraform 最重要的能力之一 ——
**资源之间的引用与自动依赖排序**。

> 前置:先做完 [day01](../day01/) 的准备工作(装 Terraform/gcloud、`gcloud auth
> application-default login`、开 `compute.googleapis.com`)。day02 独立可跑,
> 会自己建 VPC + 子网。

## 这一天的核心新知识:资源引用(依赖)

day01 只建了一个 VPC。今天多了一个子网,而子网必须"长在"某个 VPC 里。
看 `main.tf` 里这一行:

```hcl
resource "google_compute_subnetwork" "subnet" {
  ...
  network = google_compute_network.vpc.id   # ← 引用上面的 VPC
}
```

- `google_compute_network.vpc.id` 的意思是:**取名为 `vpc` 的那个资源的 `id` 属性**。
- 因为子网引用了 VPC,Terraform 会自动画出依赖关系:**先建 VPC,再建子网**。
- `destroy` 时自动反过来:**先删子网,再删 VPC**。
- 这叫 **隐式依赖(implicit dependency)** —— 你不用手写顺序,Terraform 靠"谁引用了谁"自己排。

这就是 Terraform 强大的地方:你只描述资源之间的关系,顺序它自己算。

## 跑起来

```bash
cd day02
cp terraform.tfvars.example terraform.tfvars   # 把 project_id 改成你的
terraform init
terraform plan     # 这次你会看到 Plan: 2 to add(VPC + 子网)
terraform apply    # 输 yes
```

apply 后留意终端输出:`subnet_gateway_ip` 是 GCP 自动分配的网关地址
(比如 `10.0.0.1`),说明子网真的生效了。

## 验证

```bash
gcloud compute networks subnets list --project <项目ID> --filter="name=my-first-subnet"
```
能看到 `my-first-subnet`,所属网络是 `my-first-vpc`,IP 段 `10.0.0.0/24`。

## 销毁

```bash
terraform destroy
```
注意看销毁顺序:Terraform 会**先删子网,后删 VPC**(依赖的反向),这正是隐式依赖在起作用。

## 和 day01 的区别

| | day01 | day02 |
|---|---|---|
| 创建的资源 | 1 个(VPC) | 2 个(VPC + 子网) |
| 新概念 | provider / resource / variable / output | **资源引用 + 自动依赖排序** |

## 小知识:CIDR 是什么

`10.0.0.0/24` 是一个 IP 段的写法:`/24` 表示前 24 位是网络位,后 8 位给主机,
所以这个段有 2^8 = 256 个地址(其中头尾几个被 GCP 保留)。段越小(数字越大)地址越少。

下一天(day03)会给这个网络加**防火墙规则**,或在子网里开一台**虚拟机**。
