# Day 13 — AWS App Runner:AWS 版的"Cloud Run"，但已经进入维护模式

上一次对话里聊到"Cloud Run 更像 Lambda 还是像别的什么"，结论是 Cloud Run
真正对应的不是 Lambda，而是 **AWS App Runner**——直接跑容器、监听端口就行、
不需要实现什么 Runtime API。这一天就是把这个结论**实测验证一遍**:用
App Runner 部署同一套 caller/callee demo。**过程中意外确认了一件更重要的
事情:App Runner 已经在 2026-04-30 停止对新客户开放，这个 AWS 账号
(aws-10)之前从没用过这个服务，本身"能不能建"就是这一天要验证的问题。**

## 结论先说:能建，但过程中真的踩了一个坑，而且这是"服务已进入维护模式"后的第一手体感

- ✅ **账号确实还能新建 App Runner 服务**——callee 第一次 apply 就成功了
  (耗时 4分52秒)，说明"新客户禁止"这条规则没有卡住这个账号(具体判定
  标准官方文档没写清楚，只能靠实测验证，见下文)。
- ⚠️ **caller 第一次创建直接失败**(`CREATE_FAILED`)，错误信息本身是个
  空的("`last error: %!s(<nil>)`"，Terraform AWS provider 一个已知的
  格式化 bug，把真实错误吞掉了)。查 CloudWatch 日志发现:镜像拉取成功，
  但部署在那之后就直接失败，连 `application` 日志组都没建出来——说明
  容器压根没启动，是 App Runner 控制面的问题，不是我代码的问题。
  `terraform apply` **重试一次直接就成功了**，5分32秒建完，没有做任何
  配置变更。
- 📊 **资源数量**:app stack 只有 **5 个资源**(2 个 App Runner service +
  1 个 IAM 角色 + 1 个策略绑定 + 1 个共享的 auto scaling 配置)——比
  day09(18)、day10(25)都少，和 day11 的 Cloud Run(6 个)接近，符合
  "App Runner 是 AWS 版 Cloud Run" 这个定位。

## 架构

```
                 🌐 Internet
                     │
      [ caller 的 App Runner 默认域名,公网可达 ]
                     │
      ┌──────────────▼──────────────┐
      │  caller service               │
      │  GET /hello                   │
      │    └─ 调用 https://<callee的   │
      │       App Runner 域名>/data    │
      └────────────────┬───────────────┘
                        │ 普通公网 HTTPS 调用,没有任何
                        │ 身份/网络层限制
      ┌─────────────────▼──────────────┐
      │  callee service                │
      │  也是公网可达,谁都能直接 curl    │  ← 和 day09-12 完全不同
      │  (App Runner 没有 IAM invoker  │
      │  概念,也没有默认的网络隔离)      │
      └──────────────────────────────────┘
```

## 结构

```
day13/
├── apps/                          # 复用 day10 的 caller/callee(已升级到
│                                   # RestClient),只改了提示文字
└── terraform/
    ├── ecr/                        # 镜像仓库
    ├── app/                        # 根配置:1个共享auto scaling配置 +
    │                                # 1个ECR访问角色 + 2个App Runner服务
    └── modules/
        └── apprunner-service/      # 可复用模块,caller/callee 各调用一次
```

## 和 day09-12 最核心的差异:App Runner 没有原生的"谁能调用我"限制

| | day09/10(ECS) | day11(Cloud Run IAM) | day12(Cloud Service Mesh) | day13(App Runner) |
|---|---|---|---|---|
| callee 隔离手段 | 安全组 | `roles/run.invoker` | IAM(mesh 自动附加凭证) | **没有** |
| 匿名直连 callee | 连不上(网络层挡) | 403(IAM 挡) | 403(IAM 挡) | **200，直接成功** |
| app stack 资源数 | 18/25 | 6 | 16 | **5** |

这一天验证过:`curl` 直接打 callee 的公网域名，**不带任何认证头，直接
200 成功**。这不是配置疏漏——是 App Runner 这个产品本身没有提供"限制
调用方身份"的原生能力。要做限制，只有两条路：

1. **网络层**:`aws_apprunner_vpc_ingress_connection`，把 callee 收进一个
   只有特定 VPC 才能访问的私有终端节点——需要额外建 VPC Endpoint、VPC
   Connector(给 caller 出网用)，复杂度direction接近 day10 的 VPC Lattice。
   这一天为了控制范围没有实现。
2. **应用层**:自己在代码里加认证(共享密钥、JWT 校验等)——平台完全不管，
   全靠自己写。

对比 Cloud Run(day11)"开箱即用的 IAM 授权"，App Runner 在这一点上明显
更原始——这也侧面印证了它现在"进入维护模式、不再投入新功能"的现状：
一个连服务间鉴权都没有原生方案的 serverless 容器平台，在 2026 年确实
已经落后于 Cloud Run 这类持续投入的同类产品。

## 实测踩的坑:caller 第一次创建失败，重试直接成功

```
Error: waiting for App Runner Service (...) create: unexpected state
'CREATE_FAILED', wanted target 'RUNNING'. last error: %!s(<nil>)
```

这个错误信息本身几乎没有信息量——`%!s(<nil>)` 是 Go 的 `fmt` 包在格式化
一个空指针时的输出，说明 Terraform AWS provider 拿到的错误对象本身是
`nil`，没能把 App Runner API 返回的真实失败原因传递出来。

查 CloudWatch 日志(`/aws/apprunner/day13-caller/.../service`)找到更多
线索：

```
[AppRunner] Pulling image ...caller from ECR repository.
[AppRunner] Successfully pulled your application image from ECR.
[AppRunner] Deployment with ID : ... failed.
```

镜像拉取成功，但紧接着就失败了——而且**这个 revision 从来没有生成过
`application` 日志组**，意味着容器从来没有真正启动执行到能往 CloudWatch
写日志的地步。这说明失败发生在 App Runner 控制面"拿到镜像之后、启动容器
之前"的某个环节，和应用代码本身无关。

`aws apprunner list-operations`、`describe-service` 都没有给出比"FAILED"
更具体的原因。最终处理方式：既然 `terraform plan` 已经自动把这个失败的
resource 标记为 `tainted`(需要 replace)，直接 `terraform apply` 重新触发
一次创建——**没有改任何配置，单纯重试，5分32秒后成功**。

**这条经验的价值**:和 day08 的 ALB 孤儿资源、day11/12 的 IAM/mesh 传播
延迟一样，这又是一次"平台侧的瞬时性问题，不是配置错误"的真实案例——
但这次连"根因是什么"都没查清楚(错误信息本身就是空的)，只能验证"重试
有效"。对一个已经进入维护模式、不再有新功能投入的服务来说，这种诊断
信息缺失的体验本身也是一个值得记录的观察点。

## 跑起来

```bash
# 1) 镜像仓库
cd day13/terraform/ecr && terraform init && terraform apply -auto-approve

# 2) build + push
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
cd ../../apps/callee && docker build -t <repo_url>/callee:v1 . && docker push <repo_url>/callee:v1
cd ../caller && docker build -t <repo_url>/caller:v1 . && docker push <repo_url>/caller:v1

# 3) 部署(可能第一次创建 CREATE_FAILED,重试 apply 即可,见上文)
cd ../../terraform/app
cp terraform.tfvars.example terraform.tfvars   # 填两个镜像地址
terraform init && terraform apply -auto-approve

# 4) 验证
curl $(terraform output -raw caller_url)/hello
curl $(terraform output -raw callee_url)/data   # 匿名直连也会成功

# 5) 销毁(App Runner 不会自动删关联的 CloudWatch 日志组,需要手动清理)
cd app && terraform destroy -auto-approve
cd ../ecr && terraform destroy -auto-approve
aws logs describe-log-groups --log-group-name-prefix "/aws/apprunner/<name>" \
  --query "logGroups[].logGroupName" --output text | \
  xargs -n1 -I{} aws logs delete-log-group --log-group-name {}
```

## 实测验证过的最终结果

```
Caller says hi! Called https://cearcuq2jr.us-east-1.awsapprunner.com/data
via AWS App Runner, got back: {"from":"callee","message":"Hello from the
callee service — reached via AWS App Runner, no invoker-style auth needed
(it doesn't have one)!"}
```

```bash
# 匿名直连 callee,不带任何认证:
curl https://cearcuq2jr.us-east-1.awsapprunner.com/data
# → 200，和 caller 调用得到完全相同的响应
```

## 关于"该不该用 App Runner"的诚实结论

这一天验证下来，App Runner 这个产品本身**能用、够简单**(5个资源就能跑
两服务demo，是这轮对比里资源数最少的之一)，但:

1. **已经停止对新客户开放**(2026-04-30 起)，虽然这次实测这个账号还能
   建，但官方文档没说清楚判定边界，长期依赖它风险很高。
2. **AWS 官方明确推荐迁移到 ECS Express Mode**——一个 2025/2026 才出的
   新功能，定位和 App Runner 几乎一样("一次 API 调用给你 Fargate+ALB+
   自动扩缩容"),但建立在持续投入的 ECS 生态上。
3. **服务间鉴权能力明显落后于 Cloud Run**——没有原生 IAM invoker，
   callee 默认对所有人开放，这在 2026 年的同类产品里是个明显短板。

**如果是新项目，不建议选 App Runner**——下一天(day14)会实测 AWS 官方
推荐的继任者 ECS Express Mode，看它是不是真的解决了这些问题。

## 和之前几天的关系

| | 用到/呼应的内容 |
|---|---|
| day07 | 模块调用两次(caller/callee) |
| day09/10 | ECR 仓库模式复用；两服务互调需求的直接对照基准 |
| day11 | "callee 没有原生调用方限制"对比的直接反例——Cloud Run 有 IAM invoker，App Runner 没有 |
| **day13(这次)** | **AWS App Runner 实测;确认服务仍可新建但已进入维护模式;caller 首次创建失败重试即成功的真实案例;为 day14(ECS Express Mode)对比打基础** |
