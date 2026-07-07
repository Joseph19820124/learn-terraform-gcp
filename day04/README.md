# Day 04 — 远程 state:把 state 存到 GCS(团队协作必备)

前三天,state 一直是本地的 `terraform.tfstate` 文件。今天把它挪到 **GCS 桶**里。

## 先搞懂:state 是什么、为什么要放远程

**state 是 Terraform 的"账本"**,记录它管理了哪些真实资源、它们的 ID 和属性。
放在本地(默认)有几个大问题:

| 本地 state 的问题 | 远程 state(GCS)怎么解决 |
|---|---|
| 只在你一台电脑上,同事看不到、没法协作 | 存在共享的 GCS 桶,团队都能访问 |
| 两个人同时 `apply` 会互相覆盖、把 state 搞坏 | GCS backend **自带加锁**:一个人 apply 时,另一个会被挡住等待 |
| 电脑坏了 / 文件误删 = state 丢了,资源就"失联"了 | 桶开 versioning,state 有历史版本可回滚 |
| 没法接 CI/CD(流水线拿不到你本地文件) | 流水线也能从桶里读写 state |

> GCP 的好处:GCS backend **锁是内置的**,不用像 AWS(S3 + DynamoDB)那样再单独建一张锁表。

## Bootstrap:先建存 state 的桶(先有鸡还是先有蛋)

存 state 的桶,**必须在 `terraform init` 之前就存在**(init 时就要连它)。所以它一般
用 gcloud 手工建、或用另一套 Terraform 建 —— 不能用"这一套"来建它自己的 state 桶。

```bash
# 桶名全球唯一,建议带上项目 ID。开 versioning(强烈建议,能回滚 state)。
gcloud storage buckets create gs://<你的项目ID>-tfstate \
  --location us-central1 --uniform-bucket-level-access --project <你的项目ID>
gcloud storage buckets update gs://<你的项目ID>-tfstate --versioning
```

## 配置 backend + 跑起来

```bash
cd day04

# 1) 把 backend.tf 里的 bucket 改成你上面创建的桶名
#    (backend 块不能用变量,只能写死 —— 这是 Terraform 的已知限制)

cp terraform.tfvars.example terraform.tfvars   # 改 project_id

# 2) init:这次会初始化 GCS backend(如果本地已有 state,它会问你要不要迁移过去)
terraform init

terraform plan
terraform apply     # 输 yes
```

## 验证:state 真的在 GCS 里,本地没有

```bash
# 本地【没有】terraform.tfstate 文件了:
ls                      # 看不到 terraform.tfstate

# state 在桶里:
gcloud storage ls gs://<你的项目ID>-tfstate/day04/
#   → 会看到 default.tfstate
```

`day04/` 就是 backend.tf 里的 `prefix`(桶内子目录)。同一个桶可以用不同 prefix
存放多套配置/多个环境的 state,互不干扰。

## 锁(locking)是怎么回事

`apply` 期间,GCS backend 会在桶里写一个**锁对象**;这时如果另一个人也来 `apply`,
会看到 `Error: Error acquiring the state lock`,被挡住等你完成。这就避免了两个人
同时改、把 state 写坏。全自动,你不用做任何事。

## 销毁

```bash
terraform destroy      # 删 VPC;state(现在在 GCS)也会更新成空
```

## 几个坑 / 最佳实践

- **backend 块不能用 `var.xxx`**:桶名只能写死,或用 `terraform init -backend-config="bucket=..."` 在命令行传。
- **桶名全球唯一**:GCS 桶名是全球共享命名空间,加项目 ID 后缀最保险。
- **一定开 versioning**:state 万一被写坏,能回滚到上一个版本救命。
- **state 里可能有敏感信息**(比如密码明文),所以**存 state 的桶要严格控制权限**,别公开。
- **别手动改 state 文件**:要改用 `terraform state` 子命令。

## 和前几天的区别

| | day01–03 | day04 |
|---|---|---|
| state 在哪 | 本地 `terraform.tfstate` | **GCS 桶(远程)** |
| 能团队协作/加锁吗 | 不能 | **能**(共享 + 自动锁) |

下一天可以讲:**用 workspace 或 prefix 管多环境**,或 **module(把代码模块化复用)**。
