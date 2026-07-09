# Day 07 — 把安全基线封装成可复用模块

把 day05(module 模块化)和 day06(反模式对照/安全基线)接起来:
day06 里那些"要注意的点"——镜像动态解析、SSH 默认不开、有 outputs、锁版本——
封装成一个模块 [`modules/secure-web-server/`](modules/secure-web-server/)，
然后像 day05 一样**调用两次**，证明"安全基线只写一遍，调用 N 次都自动带上"。

## 结构

```
day07/
├── main.tf              # 根配置:调用 secure-web-server 模块两次(team_a / team_b)
├── outputs.tf            # module.team_a_web.web_url / module.team_b_web.web_url
└── modules/
    └── secure-web-server/  # 可复用模块:day06 的安全基线全部封装在这里
        ├── main.tf         # 镜像动态解析 + HTTP开放/SSH默认关闭 + VM
        ├── variables.tf    # 输入接口:name / zone / message / ssh_source_ranges ...
        └── outputs.tf      # 输出接口:instance_name / public_ip / web_url
```

## 这一天的核心价值:封装安全基线

模块的意义不只是"少写代码"。看 `main.tf` 里两次调用：

```hcl
module "team_a_web" {
  source  = "./modules/secure-web-server"
  name    = "day07-team-a-web"
  zone    = var.zone
  message = "Hello from Team A! ..."
  # 没传 ssh_source_ranges —— 继承模块默认值:不开放 SSH。
}

module "team_b_web" {
  source  = "./modules/secure-web-server"
  name    = "day07-team-b-web"
  zone    = var.zone
  message = "Hello from Team B! ..."
}
```

调用方**只需要关心"名字"和"首页写什么"**，完全不用重新决定"SSH 要不要开、
镜像用哪个版本"这些安全相关的问题——因为模块已经替你把这些决定做好了，
而且是**统一**的决定。

### 好处 1:接口收窄，调用方犯不了 day06 那种错

反面教材(day06 讲的 AWS tutorial)里，SSH 是不是对全世界开放，取决于
写代码的人当时有没有想到。用了这个模块，`ssh_source_ranges` 默认就是
空列表——**除非调用方主动、显式传入自己的 IP，否则不可能重蹈覆辙**。
好的模块设计把"容易犯错的决定"从调用方手里拿走。

### 好处 2:改一处，所有调用方一起受益

如果以后想给这套"安全基线"加一条规则(比如给所有 web 服务器都装个监控
agent、或者把默认机型从 e2-micro 换成 e2-small)，只要改
`modules/secure-web-server/main.tf` **这一份文件**，`team_a_web` 和
`team_b_web`(以及未来任何调用这个模块的地方)下次 apply 都会同步生效。
不用满仓库找哪里还有个"复制粘贴"出来的 web 服务器忘了改。

## 跑起来

```bash
cd day07
cp terraform.tfvars.example terraform.tfvars   # 改 project_id
terraform init      # 会看到 Initializing modules... team_a_web / team_b_web
terraform plan      # Plan: 4 to add(2 台 VM + 2 条 HTTP 防火墙规则;SSH 规则不在其中)
terraform apply
```

apply 完看 outputs 里的 `team_a_url` / `team_b_url`，各自打开验证：两台机器
首页内容不同(因为 `message` 参数不同)，但底层安全基线完全一致。

## 验证过的关键点(实测)

- `terraform init` 显示 `Initializing modules... - team_a_web ... - team_b_web`
  ——同一份模块被实例化了两次。
- 两台机器的首页内容不同，证明 `message` 这个"内容旋钮"正常工作。
- `gcloud compute firewall-rules list` 显示只有
  `day07-team-a-web-allow-http` 和 `day07-team-b-web-allow-http`
  ——**两次调用都没有创建 SSH 规则**，安全基线在两处都生效了。

## 销毁

```bash
terraform destroy
```

## 和前几天的关系

| | day05 | day06 | day07(今天) |
|---|---|---|---|
| 学到什么 | module 化、调用多次 | 反模式 vs 最佳实践 | **把最佳实践封装进模块，调用多次** |
| 模块管什么 | 网络(VPC+子网) | (没有模块，单份代码) | **安全基线 web 服务器** |

下一天可以讲：给这个模块加参数化的**机型/磁盘大小选择**(比如小/中/大三档)，
或者把模块发布到私有的 Terraform 内部 registry / Git 引用，让"跨仓库复用"
这件事更真实。
