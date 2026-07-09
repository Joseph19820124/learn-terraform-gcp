# Day 11 — 同样的两服务互调需求，换到 GCP：Cloud Run + IAM，不需要 service mesh

day09/day10 在 AWS 上分别用 ECS Service Connect 和 VPC Lattice 解决"两个服务
互相调用"的问题。这一天在 GCP 上做同一件事，但用 **Cloud Run**(ECS Fargate
的 GCP 对应物)——结论是:GCP 这边**根本不需要引入任何 mesh 概念**，Cloud
Run 原生的 IAM 鉴权就是官方推荐的默认做法。**同样是真实写完 Terraform、真实
部署到 GCP、真实调通、真实踩了一个坑再修好、最后真实销毁验证过的一次实测。**

## 结论先说:能跑通，而且比 day09/10 都简单，但踩了一个"新手常见"的坑

- ✅ **最终跑通了**:caller 用 GCP 签发的身份令牌(identity token)调用
  callee，成功拿到最新版本的响应。
- ⚠️ **踩了一个真实的坑**:IAM 权限生效有传播延迟，第一次调用直接失败
  (见下文"实测踩的坑")。
- 📊 **资源数量对比**:day11(Cloud Run)的 app stack 只有 **6 个资源**——
  比 day09(18 个)、day10(25 个)都少得多。没有集群、没有安全组、没有负载
  均衡器、没有服务发现命名空间。

## 架构

```
                 🌐 Internet
                     │
        [ caller 的 Cloud Run URL，allUsers 可调用 ]
                     │
      ┌──────────────▼──────────────┐
      │  caller service               │
      │  GET /hello                   │
      │   1) 向 GCP metadata server    │
      │      要一个 audience=callee URL │
      │      的 identity token         │
      │   2) 带着 Authorization: Bearer │
      │      调用 callee                │
      └────────────────┬───────────────┘
                        │
      ┌─────────────────▼──────────────┐
      │  callee service                │
      │  网络层面其实是公网可路由的      │  ← 和 day09/10 最大的不同！
      │  (ingress = ALL)，但 IAM 只     │
      │  允许 caller 的服务账号调用     │
      │  (roles/run.invoker)           │
      └──────────────────────────────────┘
```

## 结构

```
day11/
├── apps/                          # 和 day09/10 类似的两个 Spring Boot app，
│                                   # 改了 PORT 环境变量支持 + identity token 逻辑
└── terraform/
    ├── registry/                   # Artifact Registry(GCP 版 ECR)
    ├── app/                        # 根配置:2 个服务账号 + 2 个 Cloud Run 服务
    └── modules/
        └── cloud-run-service/      # 可复用模块，caller/callee 各调用一次
```

## 和 day09/10 最大的架构差异:隔离层从"网络"变成"身份"

| | day09(Service Connect) | day10(VPC Lattice) | day11(Cloud Run) |
|---|---|---|---|
| callee 是否网络可达 | 否(仅同 VPC 内可达) | 否(仅 Lattice 数据面可达) | **是(公网可路由的 https URL)** |
| 隔离手段 | 安全组引用调用方安全组 ID | 安全组引用 AWS 托管 prefix list | **IAM `roles/run.invoker`** |
| 隔离发生在哪一层 | 网络层(ENI/SG) | 网络层(Lattice 数据面) | **身份层，请求到容器前就被拦截** |
| 调用方代码要做什么 | 什么都不用做(纯网络透明) | 什么都不用做(纯网络透明) | **必须主动去 metadata server 要 token，加到 Authorization 头** |
| 需要 VPC/子网/安全组吗 | 需要(默认 VPC 即可) | 需要 | **完全不需要** |
| app stack 资源数(2服务) | 18 | 25 | **6** |

这是这一天最核心的认知:AWS 的两条路径(Service Connect、Lattice)都是**网络
层面的透明代理**——应用代码完全不知道自己被"网了一层"，调用方直接拿容器
地址/DNS 名字发请求就行。GCP Cloud Run 的默认模型反过来:**网络层完全不设防
(URL 本身可以被任何人访问到)，安全边界完全交给 IAM**，但这意味着**调用方
代码必须显式参与鉴权流程**(去要 identity token、加请求头)——如果直接照抄
day09/10 那种"裸调用，不用管认证"的写法，结果就是下面这个坑。

## 应用代码的关键改动(相对 day10 直接复制过来的版本)

1. `application.yml`:`server.port: 8080` → `server.port: ${PORT:8080}`。
   Cloud Run 通过 `PORT` 环境变量告诉容器该监听哪个端口，写死 8080 在这里
   碰巧也能跑(Cloud Run 默认端口就是 8080)，但这是巧合，不是保证——正确
   做法是读环境变量。
2. `CallerApplication.java` 新增 `fetchIdentityToken()`:请求
   `http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=<callee_url>`
   (带 `Metadata-Flavor: Google` 头)，拿到的 JWT 塞进
   `Authorization: Bearer <token>` 再去调 callee。这段逻辑在 day09/10 完全
   不存在——AWS 那两条路径里，调用方的应用代码是"裸调用"，鉴权/隔离全部
   发生在网络层，应用代码感知不到。

## 实测踩的坑:IAM 权限传播延迟，第一次调用直接失败

`terraform apply` 成功创建了全部 6 个资源(2 个服务账号 + 2 个 Cloud Run
服务 + 2 条 `roles/run.invoker` 绑定)，`terraform apply` 的输出显示一切
"Creation complete"。但 apply 刚结束就立刻 `curl caller_url/hello`，caller
返回的却是 callee 的 **403 Forbidden**:

```
Caller says hi! Called https://day11-callee-.../data via Cloud Run IAM auth, got back:
<html>...<title>403 Forbidden</title>...
Your client does not have permission to get URL /data from this server.
</html>
HTTP_STATUS:200   ← 注意:caller 自己是 200，是 caller 转发的 callee 响应体里包着 403
```

用 `gcloud run services get-iam-policy day11-callee` 检查，IAM 绑定**明明
已经写进去了**、成员/角色都完全正确。这不是配置错误，是**权限传播延迟**
——服务账号和 IAM 绑定都是刚创建出来的(几十秒前)，Cloud Run 的鉴权检查
需要一点时间才能感知到最新的 IAM 状态。等了大约 45 秒后重试，请求立刻
成功:

```
Caller says hi! Called https://day11-callee-.../data via Cloud Run IAM auth, got back:
{"from":"callee","message":"Hello from the callee service — reached via
Cloud Run IAM-authenticated call (roles/run.invoker), not network isolation!"}
HTTP_STATUS:200
```

**这条经验的价值**:如果你在 CI/CD 流水线里紧跟着 `terraform apply` 之后
立刻做冒烟测试(smoke test)，用的又是刚创建的服务账号，第一次请求大概率
会因为 IAM 传播延迟而失败——这不是 bug，重试或加个短暂等待就行，但如果
不知道这个特性，很容易误判成"部署失败"去回滚或重新 apply。

## 安全模型验证(和 day09/10 同样做法，实测验证，不是纸上谈兵)

```bash
# 1) caller 调 callee:成功
curl https://day11-caller-.../hello
# → 200，返回 callee 的真实响应

# 2) 匿名直连 callee(没有任何 token):被拒绝
curl https://day11-callee-.../data
# → 403 Forbidden

# 3) 用我自己 gcloud 账号的身份令牌调 callee(有效身份，但没被授权):也被拒绝
curl -H "Authorization: Bearer $(gcloud auth print-identity-token --audiences=<callee_url>)" \
     https://day11-callee-.../data
# → 401 Unauthorized

# 4) callee 的 IAM policy:只有一条绑定
gcloud run services get-iam-policy day11-callee --region=us-central1
# bindings:
# - members: [serviceAccount:day11-caller@...]
#   role: roles/run.invoker
```

和 day09/10 的结论对比：day09 的 callee"有公网 IP 但连不上"(网络层拦截)，
day10 的 callee 同样"有公网 IP 但连不上"(网络层拦截)；day11 的 callee**是
真的公网可路由**(URL 本身谁都能发请求到)，但**没有正确身份的请求会在到达
容器代码之前就被 Cloud Run 平台拒绝**——安全效果一样(未授权者调不通)，
但实现原理完全不同。

## 环境细节:本地 Terraform 版本坑(和这天的业务逻辑无关，纯环境问题)

本机默认 `terraform` 是 1.9.8，但这个仓库(day01 起)锁定
`required_version = ">= 1.10"`，直接 apply 会报错。之前 day09/10 用的是
之前下载好放在 `/tmp/tf1157/terraform` 的 1.15.7，这天继续复用这个二进制。
（这是环境记录，不是这份 Terraform 代码的问题——只是提醒:换机器/换 CI 跑
这个仓库时，确认一下 Terraform CLI 版本。）

## 跑起来

```bash
# 1) 镜像仓库
cd day11/terraform/registry
cp terraform.tfvars.example terraform.tfvars   # 填你的 project_id
terraform init && terraform apply -auto-approve

# 2) build + push(两个 app 的代码在 apps/ 下)
gcloud auth configure-docker <region>-docker.pkg.dev
cd ../../apps/callee && docker build -t <repo_url>/callee:v1 . && docker push <repo_url>/callee:v1
cd ../caller && docker build -t <repo_url>/caller:v1 . && docker push <repo_url>/caller:v1

# 3) 部署(2 个服务账号 + 2 个 Cloud Run 服务)
cd ../../terraform/app
cp terraform.tfvars.example terraform.tfvars   # 填两个镜像地址
terraform init && terraform apply -auto-approve

# 4) 验证(如果刚 apply 完就试，可能碰到上面说的 IAM 传播延迟，重试一次就好)
curl $(terraform output -raw caller_url)/hello

# 5) 销毁
cd app && terraform destroy -auto-approve
cd ../registry && terraform destroy -auto-approve
```

## 和之前几天的关系

| | 用到/呼应的内容 |
|---|---|
| day07 | 模块调用两次(caller/callee)，参数不同 —— 这次是 `cloud-run-service` 模块 |
| day08 | ECS Fargate ↔ Cloud Run 的直接对应关系(都是 serverless 容器) |
| day09/10 | 同样的"两服务互调"需求，作为直接对照基准 —— 三种方案实测对比见上表 |
| **day11(这次)** | **Cloud Run 原生 IAM 互调实测;新发现 IAM 传播延迟的坑；确认"Cloud Run 服务间互调不需要任何 service mesh 概念"这个假设是对的** |

## 一个中途澄清过的设计问题(写在这里，方便以后回顾)

最初设计时想当然地以为:把 callee 的 `ingress` 设成 `INTERNAL_ONLY`，就能像
day09/10 那样让 callee"没有公网入口"。**查证后发现这个假设是错的**——GCP
文档写得很明确:同项目下 Cloud Run 服务之间互调，即使目标服务 `ingress =
INTERNAL_ONLY`，调用方也**不会**自动被当作"内部流量"；只有 Pub/Sub push、
Cloud Tasks、Cloud Scheduler 等少数 GCP 托管服务的调用会被自动放行，
Cloud Run 互相调用必须调用方显式接入 VPC(Direct VPC egress 或 Serverless
VPC Access 连接器)才算"内部"。这套 VPC 方案更接近 day09/10 的网络隔离
模型，但复杂度也回来了；本次实测选择了更简单、也是 GCP 官方更推荐的路径
(ingress = ALL + IAM 鉴权)，两种方案的取舍在上面的对比表里已经体现。
