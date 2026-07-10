# Day 20 — 多环境(dev/staging/prod):在 day09 的基础上加环境隔离

> ⚠️ **这一天和之前几天不一样：没有实测。** 写这份代码的环境里没有装
> `terraform`/`aws` CLI，也没有 AWS 凭证，没法像 day01–19 那样真的 `apply`
> 一遍再销毁验证。下面的坑是根据 Terraform/AWS 的已知行为**推断**出来的，
> 不是"跑出来的"。如果你要用，请先在自己有 AWS 凭证的机器上完整跑一遍
> `dev` 环境，确认没问题再碰 `staging`/`prod`。

day09 做了"两个 ECS 服务互相调用"，但从头到尾只有一套资源、一份 state。真实
项目至少要有 dev/staging/prod 三套环境：**同一份 Terraform 配置**，部署出
**三套完全独立、互不干扰**的资源，镜像还要能从 dev 验证过后原样"晋升"到
staging、prod，而不是每个环境重新 build 一遍。这一天要解决的就是这个问题。

## 架构

和 day09 完全一样(caller 挂 ALB、callee 没有公网入口、两者靠 ECS Service
Connect 按名字互调)，**乘以三**：

```
day20-dev 环境      day20-staging 环境      day20-prod 环境
┌───────────────┐   ┌───────────────┐      ┌───────────────┐
│ caller (×1)   │   │ caller (×2)   │      │ caller (×3)   │
│   │           │   │   │           │      │   │           │
│   ▼           │   │   ▼           │      │   ▼           │
│ callee (×1)   │   │ callee (×2)   │      │ callee (×3)   │
└───────────────┘   └───────────────┘      └───────────────┘
      state: day20/dev/…   day20/staging/…      day20/prod/…
      (同一个 S3 桶里，三个不同的 key —— 物理隔离)
```

三个环境用**同一份** `terraform/app` 配置、**同一个** ECR 仓库里的**同一个
镜像 tag**，只是通过变量和 backend 配置把它们导向三套不同的资源和三份不同
的 state。

## 相对 day09 的三处新增

### 1. `environment` 变量决定资源名字

```hcl
locals {
  full_name = "${var.name}-${var.environment}"   # day20-dev / day20-staging / day20-prod
}
```

集群、命名空间、两个服务、安全组……所有资源名字都从 `full_name` 派生，三个
环境即使部署到同一个 AWS 账号、同一个 region，资源名字也不会撞车。
`environment` 加了 Terraform `validation` block，只能是 `dev`/`staging`/`prod`
三选一，输错直接在 `plan` 阶段报错，不会等到 `apply` 才发现。

### 2. 环境级别的规格差异走 `environments/*.tfvars`

`desired_count` / `cpu` / `memory` 提成变量，三份 tfvars 各自给不同的值：

| | dev | staging | prod |
|---|---|---|---|
| `desired_count` | 1 | 2 | 3 |
| `cpu` | 256 | 512 | 512 |
| `memory` | 512 | 1024 | 1024 |

这一天的重点是"环境隔离"这件事本身，不是"prod 该配多大"——真实项目请按实际
负载压测后再定这几个数字。

### 3. state 隔离:S3 backend 的 partial configuration

day04 讲过把 state 放到 GCS 远程存储。这一天换成 AWS S3，而且**故意不在
`backend.tf` 里写死 bucket/key**：

```hcl
# backend.tf
terraform {
  backend "s3" {
    use_lockfile = true   # Terraform 1.10+ 原生 S3 锁，不用再建 DynamoDB 表
  }
}
```

bucket/key/region 全部留给 `terraform init -backend-config=<文件>` 在初始化
那一刻决定。三个环境各自一份 `backend-configs/*.hcl`，**唯一的区别就是
`key`**(`day20/dev/terraform.tfstate` vs `.../staging/...` vs `.../prod/...`)。
这是这一天最想强调的事：**如果三个环境共用同一份 state，一次 `dev` 的 `apply`
就可能把 `prod` 的资源改掉甚至删掉**——用不同的 key 从物理上切断这种可能性。

## 结构

```
day20/
├── apps/                         # 和 day09 完全一样，caller/callee 代码不区分环境
│   ├── caller/
│   └── callee/
└── terraform/
    ├── ecr/                      # 共享的镜像仓库(不分环境，镜像靠 tag 在环境间晋升)
    ├── modules/                  # 和 day09 完全一样，没有改一行
    │   ├── ecs-cluster/
    │   └── ecs-fargate-service/
    └── app/
        ├── backend.tf            # S3 backend，partial configuration
        ├── main.tf               # 加了 local.full_name，其余和 day09 一样
        ├── variables.tf          # 新增 environment/desired_count/cpu/memory
        ├── outputs.tf
        ├── environments/         # 三份 tfvars，环境级别的差异化配置
        │   ├── dev.tfvars
        │   ├── staging.tfvars
        │   └── prod.tfvars
        └── backend-configs/      # 三份 backend config，唯一区别是 state key
            ├── dev.hcl
            ├── staging.hcl
            └── prod.hcl
```

## 跑起来(预期步骤，未实测)

```bash
# 0) 前提:提前手动建好一个 S3 桶用来存 state(参考 day04 的 bootstrap 思路，
#    这个桶本身不能用这套 Terraform 来建 —— 先有桶，才能 init)。
#    把桶名填进 backend-configs/*.hcl 里的 bucket 字段。

# 1) 镜像仓库(三个环境共用)
cd day20/terraform/ecr
terraform init && terraform apply -auto-approve
# 记下 repository_urls

# 2) build + push 一次镜像(用一个版本 tag，三个环境共用同一个 tag)
cd ../../apps/callee
docker build -t <callee_repo_url>:v1 .
docker push <callee_repo_url>:v1
cd ../caller
docker build -t <caller_repo_url>:v1 .
docker push <caller_repo_url>:v1
# 把这两个地址填进 environments/{dev,staging,prod}.tfvars

# 3) 部署 dev
cd ../../terraform/app
terraform init -backend-config=backend-configs/dev.hcl
terraform apply -var-file=environments/dev.tfvars -auto-approve
curl $(terraform output -raw caller_web_url)   # 验证 dev 通了

# 4) 切到 staging —— 注意这里必须重新 init，因为 backend key 变了
terraform init -reconfigure -backend-config=backend-configs/staging.hcl
terraform apply -var-file=environments/staging.tfvars -auto-approve

# 5) 确认 staging 没问题后，晋升到 prod(同一个镜像 tag，不重新 build)
terraform init -reconfigure -backend-config=backend-configs/prod.hcl
terraform apply -var-file=environments/prod.tfvars -auto-approve

# 6) 销毁(倒序:先 prod/staging/dev 各自的 app，最后 ecr)
terraform init -reconfigure -backend-config=backend-configs/prod.hcl
terraform destroy -var-file=environments/prod.tfvars -auto-approve
# ...对 staging、dev 重复同样的步骤
cd ../ecr && terraform destroy -auto-approve
```

## 预期会踩的坑(根据 Terraform 已知行为推断，还没有真实跑过)

- **忘记 `-reconfigure` 直接切 backend-config**:Terraform 发现 backend
  配置变了会报错或者弹出"要不要把现有 state 迁移过去"的交互式确认，
  在 CI 里这种交互式提示会直接卡住。跨环境切换时**永远显式加
  `-reconfigure`**，避免把 dev 的 state "迁移"进 staging 的 key 里。
- **ECR `image_tag_mutability = IMMUTABLE`**:这是 day09 就有的设置，这一天
  刚好用上它的另一面——它保证"同一个 tag 在三个环境里引用的一定是同一个
  镜像"，不会有人不小心把 `v1` 覆盖成另一个内容不同的构建。但也意味着如果
  真的需要改代码，必须打新 tag(比如 `v2`)，不能复用 `v1`。
- **`terraform apply` 前务必确认当前连的是哪个环境**:`terraform workspace`
  这一天没用(故意用目录级的 `-backend-config`/`-var-file` 而不是
  workspace，原因见下)，所以唯一的保险是每次 apply 前跑一下
  `terraform show | head` 或检查 `.terraform/environment` 之类的痕迹，
  确认 state 确实是你以为的那个环境——纯目录切换缺少 workspace 那种
  "当前 workspace 名字"的显式提示，人为看错环境是这个方案最大的风险点。
- **三个环境的 IAM/网络権限**:这个 demo 仍然用 default VPC + 公有子网，
  三个环境的 ECS 执行角色也是分别新建的(`day20-dev-*-ecs-execution` 等)，
  不共享——如果真实项目要控制"谁能碰 prod"，应该在这基础上加 AWS Organizations
  的账号级隔离或者至少是 IAM 权限边界，这一天没有做到那么细。

## 为什么不用 Terraform workspace

Terraform 原生的 `terraform workspace new dev/staging/prod` 也能做环境隔离，
但社区公认的坑是:**同一份 backend key 前缀 + workspace 后缀**这种模式很容易
让人在错误的 workspace 下执行 apply(命令行不会用力提醒你当前在哪个
workspace),而且没法给不同 workspace 用完全独立的 tfvars 文件(workspace
本身不带变量,还是得配合 `-var-file`)。这一天选择"目录级 `-backend-config` +
`-var-file`"这种更笨但更显式的方式——每次操作都要手动指定环境，出错的代价是
"忘记加参数导致命令报错"，而不是"悄悄 apply 到了错误的环境"。这是两种方案的
权衡，不是说 workspace 不能用。

## 和之前几天的关系

| | 用到的概念 |
|---|---|
| day04 | 远程 state(GCS)——这次搬到 AWS S3，加了 partial configuration 应对多环境 |
| day05/day07 | 模块化、模块调用多次——这次是同一套模块被三个环境各自调用一遍 |
| day09 | 两服务架构本身(ECS Service Connect + 精细安全组)完全没变 |
| **day20(这次)** | **同一份配置的多环境部署**：环境级命名、环境级规格差异化、环境级 state 隔离 |

## 一句话总结

> 多环境不是"复制三份 Terraform 代码"，而是**同一份配置 + 三份变量输入
> (tfvars)+ 三份 state 位置(backend config)**。资源名字、规格、state 全部
> 从 `environment` 这一个变量派生，环境之间物理隔离但代码零重复——这一天在
> day09 已经跑通的两服务架构上验证了这个模式，但受限于当前环境没有 AWS
> 凭证，还没有真的三个环境各 apply 一遍，这部分需要你自己在有权限的地方补测。
