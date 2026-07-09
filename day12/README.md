# Day 12 — Cloud Service Mesh:day10 VPC Lattice 的 GCP 对照

day10 在 AWS 上把 day09 的 ECS Service Connect 换成了 VPC Lattice，验证"引入
真正的 service mesh/网络产品之后，复杂度和收益分别是什么"。这一天在 GCP 上
做同一件事:把 day11(Cloud Run + 纯 IAM 互调)升级成 **Cloud Service Mesh**
(Anthos Service Mesh + Traffic Director 整合改名后的产品，2026 年已扩展到
支持 Cloud Run，不再局限于 GKE)。**这是目前为止四天(day09-12)里踩坑最多、
调试时间最长的一次，而且这次的坑很多是"文档没写全，得从报错和源码线索里
反推"的类型——过程如实记录在下面。**

## 结论先说:能跑通，但目前这仍然是一个 **Preview** 阶段功能，复杂度和不确定性都明显更高

- ✅ **最终跑通了**:caller 通过 Envoy sidecar、以 mesh 内部主机名调用 callee，
  重复调用 3 次全部成功，callee 的最新响应内容验证无误。
- ⚠️ **踩了三个真实的坑**,比 day08-11 加起来还多(下面详细写),其中两个是
  官方文档没有直接说清楚、需要看报错日志反推根因的那种。
- 📊 **资源数量对比**:day12 的 app stack 是 **16 个资源**——比 day11(纯
  IAM,6 个)多了 10 个:VPC、子网、mesh 资源、2 个服务账号、project IAM
  绑定、time_sleep、Serverless NEG、backend service、私有 DNS zone + 记录、
  HTTPRoute。
- 🚧 **这个功能目前是 Pre-GA(Preview)**:Google 官方文档明确写着"subject to
  the Pre-GA Offerings Terms"，Terraform 里对应的 `service_mesh` block 也
  标注为 Beta,必须用 `google-beta` provider、`launch_stage = "BETA"` 才能用。

## 架构

```
                 🌐 Internet
                     │
        [ caller 的 Cloud Run URL，allUsers 可调用 ]
                     │
      ┌──────────────▼──────────────────────┐
      │  caller service(接了 --mesh)          │
      │  ┌─────────────────────────────────┐ │
      │  │ 应用容器:GET /hello              │ │
      │  │  → http://callee.day12.internal │ │
      │  └────────────┬────────────────────┘ │
      │  ┌─────────────▼────────────────────┐ │
      │  │ Envoy sidecar(平台自动注入)       │ │  ← day11 没有这一层
      │  │ 拦截出站流量,查 mesh 控制面路由    │ │     应用代码不用管认证
      │  │ 规则,自动附加身份凭证             │ │
      │  └────────────┬────────────────────┘ │
      └───────────────┼──────────────────────┘
                       │ Direct VPC egress
      ┌────────────────▼──────────────────┐
      │  VPC + 子网(day12-vpc)            │  ← day11 完全不需要
      │  Private DNS zone(day12.internal) │     VPC/DNS/mesh 这一整套
      │  Mesh 资源(day12-mesh)            │
      └────────────────┬──────────────────┘
                       │ HTTPRoute:callee.day12.internal → backend service
      ┌────────────────▼──────────────────┐
      │  Serverless NEG + Backend Service   │
      │  (INTERNAL_SELF_MANAGED)           │
      └────────────────┬──────────────────┘
      ┌────────────────▼──────────────────┐
      │  callee service(普通 Cloud Run)    │
      │  代码和 day11 一模一样,不用加入 mesh │
      │  只允许 caller 的服务账号调用       │
      └──────────────────────────────────────┘
```

## 结构

```
day12/
├── apps/                          # caller 去掉了 day11 的 identity-token
│                                   # 代码(mesh 帮你做了);callee 和 day11 相同
└── terraform/
    ├── registry/                   # Artifact Registry
    ├── app/                        # 根配置:VPC+子网、mesh、DNS、NEG、backend
    │                                # service、HTTPRoute、caller/callee 两个服务
    └── modules/
        └── cloud-run-service/      # day11 模块 + 一个可选的 join_mesh 开关
```

## 和 day09-11 的核心对比:鉴权责任在哪一层，随方案不同来回搬

| | day09 SC | day10 Lattice | day11 IAM | day12 Mesh |
|---|---|---|---|---|
| 调用方代码要写认证逻辑吗 | 否 | 否 | **要(手动拿 identity token)** | 否(Envoy 自动做) |
| 隔离/鉴权发生在哪层 | 网络(SG) | 网络(Lattice 数据面) | 身份(IAM) | 身份(IAM)+ mesh 路由层 |
| app stack 资源数(2服务) | 18 | 25 | **6** | **16** |
| 需要 VPC 吗 | 需要(默认VPC) | 需要 | **不需要** | 需要(专门建) |
| 功能成熟度 | GA | GA | GA | **Preview/Beta** |

day11 → day12 是这四天里最有意思的一次"来回"：day09/10 里应用代码完全不管
认证(全在网络层)；day11 把认证责任丢给了应用代码(手动拿 token)；day12
引入 mesh 之后，认证责任**又还回了基础设施层**——但代价是资源数量、配置
复杂度、以及本 day 实测踩的三个坑，全都比 day11 高出一个量级。

## 实测踩的三个坑(这是目前为止最多的一次)

### 坑 1:`service_mesh` block 用默认 `google` provider 直接报错

第一次写完 Terraform 跑 `validate`，报错:
```
Error: Unsupported block type
Blocks of type "service_mesh" are not expected here.
```
查 Terraform provider 官方文档才发现:这个 block 是 **Beta**,示例代码里
明确写着 `provider = google-beta`、`launch_stage = "BETA"`——用默认的
`google` provider 声明这个 block，provider 的 schema 里根本不认识它，
直接报"未知 block"。修法:给用到 `service_mesh` 的 `google_cloud_run_v2_service`
资源额外声明 `google-beta` provider(项目里额外配置一个 `provider
"google-beta" {...}`),并给 caller 设置 `launch_stage = "BETA"`。

### 坑 2:mesh 刚建完,caller 立刻引用会失败——Envoy sidecar 卡死,201 次探针全部失败

修完坑 1 后第一次真实 apply,caller 服务创建失败:
```
Error waiting to create Service: Error code 9, message: The user-provided
container failed to start and listen on the port defined provided by the
PORT=8080 environment variable within the allocated timeout.
```
查 Cloud Run 日志(不是 Terraform 报错本身,报错信息完全没提到根因，
必须去看 revision 日志才找得到):
```
Default STARTUP HTTP probe failed 200 times consecutively for container
"cloud-run-mesh-proxy" on port 15020 path "/healthz".
Contents: Envoy not ready, phase=ENVOY_PHASE_SERVER_STATE_PRE_INITIALIZING
```
关键线索:失败的不是我写的应用容器,是 Cloud Run 平台自动注入的 Envoy
sidecar(容器名 `cloud-run-mesh-proxy`)——它卡在"预初始化"阶段一直没好,
说明它没能成功连上 mesh 控制面拿配置。

根因排查下来是两个问题叠加:
1. **子网没开 Private Google Access**:Envoy 要连 `trafficdirector.googleapis.com`
   这类 Google API 才能拉到 mesh 路由配置,子网没开这个,这条路走不通。
2. **更关键的一个疏漏**:`google_project_iam_member.caller_trafficdirector`
   (给 caller 服务账号授予 `roles/trafficdirector.client`)这个资源，
   根本没有被声明成 `module.caller` 的依赖——Terraform 完全可能先创建
   caller 服务、IAM 绑定还没生效甚至还没创建，这不是"等的时间不够"，
   是"压根没等"。

修法:子网加 `private_ip_google_access = true`；`time_sleep.wait_for_mesh`
的 `depends_on` 里补上这条 IAM 绑定,等待时间从 60s 拉到 90s；`module.caller`
显式 `depends_on` 这个 time_sleep。改完之后重新 apply,一次成功，
`curl /hello` 连续 3 次全部 200。

**这条经验的价值**:Terraform 的报错信息本身("容器没监听端口")具有很强的
误导性——第一反应会怀疑是应用代码或者 Dockerfile 的问题,但实际根因完全在
基础设施配置(网络出网路径 + IAM 依赖关系)上,和应用代码毫无关系。遇到
"Cloud Run 容器启动超时"类报错，第一步应该去看 revision 日志里具体是哪个
容器(你自己的还是平台注入的 sidecar)在失败，而不是先怀疑自己的代码。

### 坑 3:`terraform destroy` 卡住——Direct VPC egress 留下的 IP 预留资源释放极慢

`terraform destroy` 执行到子网这一步直接报错：
```
Error: The subnetwork resource '.../subnetworks/day12-subnet' is already
being used by '.../addresses/serverless-ipv4-1783631636121585632',
resourceInUseByAnotherResource
```
这是 Cloud Run Direct VPC egress 在子网里自动预留的一个内部 IP 地址资源，
caller 服务本身已经删除干净了，但这个预留没有跟着立刻释放。手动
`gcloud compute addresses delete` 也删不掉：
```
Error: The address resource '...' is already being used by
'//serverless.googleapis.com/.../addressReservations/...'
```
这个预留被 `serverless.googleapis.com` 自己的一个内部资源锁着，用户侧
没有直接删除的办法(`gcloud compute addresses delete` 也报同样的
"in use by addressReservations"错误)，只能等 Google 的控制面异步释放。

**实测最终等了约 100 分钟才释放**——中途每隔几分钟轮询一次，地址状态
一直是 `RESERVED`、`users` 字段一直是空(意味着没有任何资源在实际使用
它，纯粹是控制面还没清理内部记录)。这比 day08 那次 ALB
`deregistration_delay`(5-6 分钟)、或者以往遇到过的 Cloud SQL 私有连接
peering 释放延迟都要长一个数量级。好消息是这两个卡住的资源(VPC、子网)
本身完全不计费(纯内部地址，没有 NAT、没有计算实例)，所以不着急也不会
产生额外费用；地址一旦释放，`terraform destroy` 立刻顺利完成，不需要
任何手动干预或状态修复。

这是继 day08(ALB target group)、以及此前遇到过的 Cloud SQL 私网 peering
之后，第三次踩到同一类问题的不同实例:**云平台的"生产者-消费者"资源释放
经常是异步的，且延迟上限没有文档承诺(本次 100 分钟，前两次是几分钟)。
Terraform 的 `destroy` 在这类场景下不能假设"删除请求发出=资源已释放"，
更不能假设"以前见过 5 分钟这次也差不多"——只能反复轮询、等它真正清空，
必要时判断这类残留资源是否计费，不计费就不用为了赶时间去做更激进的操作。**

## 跑起来

```bash
# 1) 镜像仓库
cd day12/terraform/registry
cp terraform.tfvars.example terraform.tfvars   # 填 project_id
terraform init && terraform apply -auto-approve

# 2) build + push
gcloud auth configure-docker <region>-docker.pkg.dev
cd ../../apps/callee && docker build -t <repo_url>/callee:v1 . && docker push <repo_url>/callee:v1
cd ../caller && docker build -t <repo_url>/caller:v1 . && docker push <repo_url>/caller:v1

# 3) 部署前记得先启用这几个 API(文档没有自动化命令,得手动/额外 apply 启用):
#    networkservices.googleapis.com networksecurity.googleapis.com
#    trafficdirector.googleapis.com vpcaccess.googleapis.com
gcloud services enable networkservices.googleapis.com networksecurity.googleapis.com \
  trafficdirector.googleapis.com vpcaccess.googleapis.com --project=<PROJECT_ID>

# 4) 部署(VPC+子网、mesh、DNS、NEG、backend service、HTTPRoute、两个 Cloud Run 服务)
cd ../../terraform/app
cp terraform.tfvars.example terraform.tfvars   # 填两个镜像地址
terraform init && terraform apply -auto-approve

# 5) 验证
curl $(terraform output -raw caller_url)/hello

# 6) 销毁(子网可能会因为坑 3 卡住,需要等待重试)
cd app && terraform destroy -auto-approve
cd ../registry && terraform destroy -auto-approve
```

## 实测验证过的最终结果

```
Caller says hi! Called http://callee.day12.internal/data via Cloud Service
Mesh (Envoy sidecar handled auth), got back: {"from":"callee","message":
"Hello from the callee service — reached via Cloud Service Mesh (Envoy
sidecar + Serverless NEG), no manual token code needed!"}
```

安全模型验证：
- 匿名直连 callee 的真实 Cloud Run URL:403(和 day11 一样,IAM 拦下)。
- 直连 `callee.day12.internal`(mesh 内部主机名):在 mesh 外部根本连不上，
  这个域名只在私有 DNS zone 里、且只有接了这个 VPC 的资源才能解析到。
- `roles/run.invoker` 仍然只给了 caller 的服务账号——**mesh 解决的是
  "调用方怎么发现目标、怎么附加凭证"，不是替代 IAM 授权本身**，这一点
  从 day11 到 day12 都没变。

## Cloud Run 上到底要不要上 service mesh？

day09→day11 这条线索验证下来的结论：如果只是"同项目/同环境下几个 Cloud
Run 服务互相调用"，**day11 的纯 IAM 方案完全够用**——6 个资源，没有 VPC、
没有 mesh、应用代码写几行拿 token 的逻辑就完事，成熟稳定(GA)。这一天
(day12)验证的 Cloud Service Mesh 换来的是:应用代码更干净(不用手写认证)、
未来可以加流量分割/mTLS/可观测性这些更高级的 mesh 能力——但代价是资源
数量翻倍还多、目前还是 Preview 阶段、而且实测踩坑数量远超其它几天。
**除非明确需要 mesh 独有的能力(渐进式发布、细粒度流量策略、跨服务网络级
可观测性),不然对于"几个 Cloud Run 服务互调"这种基础场景，day11 的方案
性价比更高。**

## 和之前几天的关系

| | 用到/呼应的内容 |
|---|---|
| day07 | 模块调用两次(caller/callee) |
| day10 | 同样"引入 mesh/网络产品"的实测思路,作为 GCP 侧对照 |
| day11 | 直接对照基准:同样的 Cloud Run 双服务,少了 mesh |
| **day12(这次)** | **Cloud Service Mesh 实测;三个坑全部来自"文档没写全，得看日志反推"，比前几天更接近真实踩坑排障的样子** |
