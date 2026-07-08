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

**锁 = 防止两个 Terraform 同时改同一份 state 的"互斥"。**

一次 `apply` 是:读 state → 算 diff → 改云资源 → 写回新 state。如果两人同时 apply 同一份
远程 state,会各自读到同一起点、各自改、都写回 —— **后写的把先写的覆盖掉**,state 就错乱了
(资源失联或被重复创建)。

所以在写 state 之前,Terraform 先**抢锁**:往桶里写一个"占用中"的记录(含
`LockID / 谁 / 什么操作 / 时间`)。抢到才干活,干完删掉(**释放**)。这期间另一个人来 apply
会看到:

```
Error: Error acquiring the state lock
Lock Info: ID xxx, Who: you@..., Operation: apply, ...
```

打个比方:就是厕所门上那块"**有人**"的牌子,或编程里的 mutex。全自动,你不用做任何事。
(如果谁 apply 到一半崩了、锁没释放,用 `terraform force-unlock <ID>` 手动解。)

## 为什么 GCS 不用锁表,而 AWS S3 要外挂 DynamoDB?(高频面试点)

关键在于:**"抢锁"这个动作必须是原子的,而且支持"仅当它还不存在时才创建成功"**
(专业叫**条件写 / compare-and-set**)。否则两人同时抢会都以为抢到了(竞态),锁就失效。

| | **GCS(GCP)** | **S3(AWS,传统)** |
|---|---|---|
| 强一致性 | ✅ 天生就有 | 早期是最终一致性(2020 才变强一致) |
| 原子条件写("仅当不存在才写") | ✅ 天生支持(`x-goog-if-generation-match: 0`) | 传统上**没有**(2024 才加 `If-None-Match`) |
| 结果 | **桶自己就能当锁**:抢锁=用"仅当不存在"写一个 `.tflock` 对象,第二个人原子失败 | S3 自己做锁不可靠 → **外挂 DynamoDB** |

- **GCS**:天生具备"强一致 + 原子条件写",所以**一个桶就能同时存 state 和实现锁**,不需要第二个服务。
- **S3(传统)**:当年 S3 没有可靠的原子条件写,而 **DynamoDB 支持条件写(`attribute_not_exists`)、强一致、原子**,正好能当可靠的互斥器。于是分工变成:**S3 存 state 数据,DynamoDB 只当"锁 + state 校验值"的协调器**。这就是 AWS 教程里总是 "S3 + DynamoDB 一对" 的原因。

**2026 的新变化**:AWS 2020 让 S3 变强一致、2024 给 S3 加了条件写,于是**新版 Terraform(1.10+)
的 S3 backend 支持 S3 原生锁**(`use_lockfile = true`),**DynamoDB 变成可选**。但海量存量项目
还是老配方,面试和工作里还会经常见到。

> 一句话:**锁靠"原子条件写"实现。GCS 天生支持,所以自己就能锁;S3 传统上不支持,只能外挂
> DynamoDB —— 如今 S3 也支持了,DynamoDB 变可选。**

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
