# Day 05 — module 模块化:把网络封装成可复用模块,调用两次

day02 我们写了"VPC + 子网"。如果 dev、staging、prod 都要这套,难道复制粘贴三遍?
不。把它封装成一个 **module(模块)**,写一遍、到处调用。

## 核心概念

- **模块 = 一个装着 .tf 的文件夹**,对外通过 **variables(输入)** 和 **outputs(输出)** 提供接口。
- **根模块(root module)**:你实际跑 `terraform` 的那个目录(这里是 `day05/`)。
- **子模块(child module)**:被根模块调用的文件夹(这里是 `modules/network/`)。
- 用 `module "名字" { source = "...", 参数... }` 来**调用**;同一个模块可以**调用多次**,每次传不同参数 = 得到一套独立资源。

## 这个 demo 的结构

```
day05/
├── main.tf            # 根配置:调用 network 模块【两次】(app 和 data)
├── variables.tf       # 根的变量(project_id / region)
├── outputs.tf         # 取模块的输出:module.app_network.vpc_name ...
└── modules/
    └── network/       # ← 可复用模块:建 VPC + 子网
        ├── main.tf
        ├── variables.tf   # 模块的输入接口:name / region / subnet_cidr
        └── outputs.tf     # 模块的输出接口:vpc_id / subnet_id ...
```

看 `main.tf`:同一个 `./modules/network`,调用了两次,一次 `name="app"`、一次 `name="data"`,
CIDR 也不同。**结果是两套 VPC+子网,但网络的"建法"只写了一遍。**

## 几个关键点

- **模块里不写 provider / backend**:子模块自动继承根配置的 provider。模块只管"建什么资源"。
- **取模块输出**:`module.app_network.vpc_name` —— `module.<调用时起的名字>.<输出名>`。
- **`source` 可以是**:本地路径(`./modules/network`)、Terraform Registry(官方/社区现成模块)、
  Git 仓库、等等。今天用最简单的本地路径。
- **必须 `terraform init`**:init 会"注册/下载"模块(哪怕是本地模块也要 init 一下)。

## 跑起来

```bash
cd day05
cp terraform.tfvars.example terraform.tfvars   # 改 project_id
terraform init      # 会看到 "Initializing modules..."
terraform plan      # Plan: 4 to add(2 个 VPC + 2 个子网)
terraform apply     # 输 yes
```

apply 后 outputs 会打印 `app-vpc / app-subnet / data-vpc / data-subnet`。

## 验证

```bash
gcloud compute networks list --project <项目ID> --filter="name~'app-vpc|data-vpc'"
```
能看到 `app-vpc` 和 `data-vpc` 两个 —— 都来自同一份模块代码。

## 销毁

```bash
terraform destroy
```

## 为什么模块化很重要(面试常问)

- **复用 / DRY**:一套网络写一遍,dev/staging/prod 或多个项目都能调用,不用复制粘贴。
- **一致性**:大家都用同一个模块 = 建出来的东西标准、少出错。
- **封装**:调用方只需关心"输入什么、得到什么输出",不用懂模块内部细节。
- **可维护**:改一处模块,所有调用方一起受益。

> 回顾:day04 的"远程 state" + 今天的"模块化",正是团队协作生产环境的两大基石。

## 和前几天的区别

| | 之前 | day05 |
|---|---|---|
| 代码组织 | 所有资源写在一个目录 | 抽成**可复用模块**,根配置只负责"调用 + 传参" |
| 复用 | 复制粘贴 | 一份模块,调用 N 次 |

下一天可以讲:**用 module + 变量做多环境(dev/staging/prod)**,或 **开虚拟机 + 防火墙**。
