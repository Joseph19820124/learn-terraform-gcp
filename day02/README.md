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

## 新手坑:同名 ≠ 复用(理解 Terraform state)

常见疑问:"我 day01 建的 VPC 没删,day02 也用同一个名字,能直接用上它吗?"
**不能,会报错。** 如果 GCP 里已经有 `my-first-vpc`,再跑 day02 会得到:

```
Error: Error creating Network: googleapi: Error 409:
The resource '.../global/networks/my-first-vpc' already exists, alreadyExists
```

**为什么?** Terraform 靠一个叫 **state(状态文件 `terraform.tfstate`)** 的东西记账,
记录"我管理了哪些真实资源、它们的真实 ID"。而 **day01 和 day02 是两个独立目录、
各有各的 state,互不认识**。所以跑 day02 时:

- day02 的 state 是空的,不知道 day01 已经建过那个 VPC;
- 它看到代码要一个 `my-first-vpc`,就去 GCP **创建**;
- 但 GCP 里已有同名 VPC(名字在一个项目里必须唯一)→ **409 冲突**。

> 核心观念:**Terraform 认资源靠 state 里记的 ID,不靠"名字碰巧一样"。**
> 名字相同不会让 day02 自动"接管"day01 的 VPC,反而会撞车。

**怎么办?**
1. 学习时最简单:day01 学完就 `terraform destroy`,day02 从零开始。
2. 想两个并存:把 day02 的 `vpc_name` 改成别的名字。
3. 想让 day02 **用已存在的 VPC**:那就不是"再创建",而是 **data source(引用)** 或
   **import(接管)**——正是 [day03](../day03/) 要讲的。

## 下一天

[day03](../day03/):**data source** 和 **import** —— 怎么在 Terraform 里"用上"已经存在的资源,以及这两者的区别。
