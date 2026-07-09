# Day 06 — 常见反模式与最佳实践对照(真实案例)

不是虚构的例子。这一天用一份**真实存在的公开教程代码**
([JayaprakashKV/terraform-tutorial](https://github.com/JayaprakashKV/terraform-tutorial/tree/main/terraform)，
AWS EC2 + httpd 的入门 demo)当反面教材，逐条对照怎么改成更规范的写法，
并在 [`good-practice/`](good-practice/) 里给出**功能对等**（同样是"起一台机器 + 装 web
server + 能访问首页"）但改掉了这些问题的 **GCP 版本**——两份都真跑过、验证过。

## 两份代码功能对等，但云平台和写法不同

| | ❌ 反面教材(AWS) | ✅ 本日改写(GCP) |
|---|---|---|
| 云 | AWS(EC2) | GCP(Compute Engine) |
| 效果 | 起一台 t2.micro，装 Apache，首页 "Welcome to the Terraform Web App" | 起一台 e2-micro，装 nginx，首页 "...(GCP edition)" |
| 代码位置 | 原 repo（未收录进本仓库，见上方链接） | [`good-practice/`](good-practice/) |

## 逐条反模式对照

### 1. 镜像 ID 写死 vs 用 image family 动态解析

```hcl
# ❌ 反面教材：写死一个具体 AMI ID
variable "ami" {
    default = "ami-0453ec754f44f9a4a"
}
```
实测：这个 AMI 从 **2025-02-20 起就被标记 Deprecated**——教程写的时候是新的，
现在已经"过期"了。AWS 目前还允许用它启动实例，但随时可能被彻底下架，
到时候这份代码直接报错 `InvalidAMIID`，没人知道怎么修。

```hcl
# ✅ 本日改写：用 data source 查"当前这个镜像家族最新可用版本"
data "google_compute_image" "web" {
  family  = "debian-12"
  project = "debian-cloud"
}
```
`family` 不是具体版本号，是一整条产品线；Google/AWS 都会持续把家族指向
未废弃的最新版本。**每次 apply 都自动拿到当时能用的镜像，不会腐坏。**
（AWS 也有等价写法：用 `data "aws_ami"` + `most_recent = true` + `owners` 过滤，
同样不写死具体 ID。）

### 2. 变量没有 description vs 每个变量都说明用途

```hcl
# ❌ 反面教材：变量名之外没有任何说明
variable "instance_type" {
    default = "t2.micro"
}
```
```hcl
# ✅ 本日改写
variable "machine_type" {
  description = "机型(e2-micro 是 GCP 里最小最便宜的机型之一，跑一个 nginx 綽綽有余)"
  type        = string
  default     = "e2-micro"
}
```
`description` 不是装饰——`terraform plan` 报错、`terraform-docs` 生成文档、
IDE 悬浮提示都会用到它。没有它，别人（或几个月后的你）只能去翻资源定义
反推这个变量是干嘛的。

### 3. 没有 outputs.tf vs apply 完直接给你要的信息

反面教材的 4 个文件里**没有 `outputs.tf`**。`apply` 完你根本不知道公网 IP 是什么，
得自己再跑一次 `aws ec2 describe-instances` 去查（我们实测时就是这样拿到 IP 的）。

```hcl
# ✅ 本日改写：apply 完直接打印访问地址
output "web_url" {
  value = "http://${google_compute_instance.web.network_interface[0].access_config[0].nat_ip}/"
}
```

### 4. 安全组无差别开放 vs 按端口拆分、默认最小暴露面(核心差异)

```hcl
# ❌ 反面教材：HTTP 和 SSH 一起对全世界开放
ingress {
    from_port = 80
    cidr_blocks = ["0.0.0.0/0"]
}
ingress {
    from_port = 22           # ← SSH 也对全世界开！
    cidr_blocks = ["0.0.0.0/0"]
}
```
HTTP 对全世界开放是 web 服务器的**预期行为**，没问题。**SSH 对全世界开放是真正的风险**
——任何人都能对你的机器做密码/密钥暴力破解尝试。这是新手教程最常见的坏习惯之一。

```hcl
# ✅ 本日改写：HTTP 单独一条规则(预期开放)；SSH 默认不开放，
# 只有显式传入你自己的 IP 才创建这条规则
variable "ssh_source_ranges" {
  type    = list(string)
  default = []   # 默认空 = 默认不开 SSH
}

resource "google_compute_firewall" "allow_ssh" {
  count          = length(var.ssh_source_ranges) > 0 ? 1 : 0
  source_ranges  = var.ssh_source_ranges   # 你自己的 IP，不是 0.0.0.0/0
  ...
}
```

**⚠️ 实测中的意外发现，非常值得记住**：即使这份 Terraform 代码本身没有创建任何
SSH 规则，`curl`/连接测试显示 **22 端口居然是通的**！一查防火墙规则列表，
发现 GCP 项目的 `default` 网络里**自带一条 `default-allow-ssh`（0.0.0.0/0, tcp:22）**
——这是 GCP 创建默认 VPC 时**自动附赠**的规则，不是任何 Terraform 代码建的。

> **教训**：Terraform 只管它 state 里记录的资源；平台/账号本身的历史遗留配置、
> 默认规则，Terraform 完全不知情、也不会主动帮你审计。**写"安全"的 IaC 代码
> 不等于环境是安全的**——生产环境要么不用 `default` 网络（建自定义 VPC），
> 要么显式审计并收紧 `default-allow-ssh` / `default-allow-rdp` 这类自动生成的规则。

### 5. 没有版本锁定 vs 锁定 Terraform + provider 版本

```hcl
# ❌ 反面教材：provider.tf 完全没有版本约束
provider "aws"{
    region = var.region
}
```
```hcl
# ✅ 本日改写(和 day01 起一直坚持的写法)
terraform {
  required_version = ">= 1.10"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 7.39" }
  }
}
```
没锁版本，日后 provider 出 breaking change，这份代码可能直接跑不动，
而且没人知道"能跑的那个版本"具体是哪个。

## 跑起来(和前几天一样的流程)

```bash
cd day06/good-practice
cp terraform.tfvars.example terraform.tfvars   # 改 project_id
terraform init
terraform plan     # 注意看:SSH 防火墙不在计划里(因为 ssh_source_ranges 默认空)
terraform apply
# apply 完直接看 outputs 里的 web_url，用浏览器/curl 打开验证
terraform destroy  # 用完记得拆
```

## 总结:5 条反模式 → 5 条对策

| # | 反模式 | 对策 |
|---|---|---|
| 1 | 镜像/AMI ID 写死 | 用 image family / `most_recent` 过滤，动态解析 |
| 2 | 变量没有说明 | 每个变量写 `description` |
| 3 | 没有 outputs | apply 完直接给出关键信息，不用手动去查 |
| 4 | 安全组无差别开放 | 按端口拆分规则；敏感端口(SSH)默认不开，显式传入才开 |
| 5 | 没锁版本 | `required_version` + `required_providers` 锁死 |

外加一条**意外但重要的收获**：**代码写得安全 ≠ 环境是安全的**，平台默认配置
（如 GCP 的 `default-allow-ssh`）需要单独审计。

下一天可以讲:自定义 VPC(不用 default 网络)、或者把这个 web app 也接进
day05 学的 module 里，做成可复用的"安全基线 web 服务器"模块。
