# Day 03 — 用上"已经存在"的资源:data source vs import

day02 结尾那个疑问("VPC 已存在,能直接用吗?")的正规解法,就是今天的两个工具:
**data source(引用)** 和 **import(接管)**。它们都能"用上现有资源",但**含义完全不同**。

## 一句话区别

- **data source = 借用/查阅**:我只想**读**它、拿它的属性来用,**绝不碰它**(不改、不删)。它归别人管。
- **import = 接管/收编**:我要把这个现有资源**纳入我的 Terraform 管理**,以后由我改、由我删。它归我管。

## 对比表

| | **data source(引用)** | **import(接管)** |
|---|---|---|
| 目的 | 读取一个"别处管理"的现有资源,用它的属性 | 把现有资源纳入**本 config** 的管理 |
| 谁拥有它 | 不是你 —— Terraform 只读 | 变成你 —— Terraform 之后能改/删它 |
| 写法 | `data "类型" "x" {}`,引用 `data.类型.x.属性` | `resource` 块 + `import {}` 块(或 `terraform import` 命令) |
| 进 state 吗 | **不进**(每次 plan 现查) | **进**(之后归 Terraform 管) |
| `terraform destroy` 会删它吗 | **不会**(不归它管) | **会**(已归它管) |
| 典型场景 | 用网络团队建好的 VPC、现有 DNS zone、现有镜像 | 把手工建的、或别的工具建的资源迁到 Terraform 管 |

## 两个可跑的 demo

- [`data-source/`](data-source/) — 用 data source **引用**一个现有 VPC,并在里面建子网。
  destroy 后子网被删、**VPC 还在**(因为 Terraform 从没拥有它)。
- [`import/`](import/) — 用 `import {}` 把一个现有 VPC **接管**进 state。
  之后 destroy,**VPC 会被删**(因为已归 Terraform 管)。

两个 demo 的 README 里都有"先用 gcloud 手工建一个现有资源"的步骤(模拟"别处已经建好的东西"),然后分别演示引用 / 接管。

## 怎么选?

- 只是想**读现有资源的值**(它由别人/别的团队负责)→ **data source**。
- 想把现有资源**变成你 Terraform 代码的一部分、以后归你管**→ **import**。

> 记忆法:**data 是"看"(read-only),import 是"收"(take ownership)。**

> 前置:装好 Terraform(>= 1.10;`import {}` 块需要 1.5+)、gcloud,做过
> `gcloud auth application-default login`,并开了 `compute.googleapis.com`。
