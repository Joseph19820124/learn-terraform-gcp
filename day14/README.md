# Day 14 — ECS Express Mode:App Runner 官方推荐的继任者，实测最多坑的一天

day13 验证了 App Runner 已进入维护模式、AWS 官方推荐迁移到全新的
**ECS Express Mode**(2025-11 发布)。这一天就是实测这个继任者:同样的
caller/callee 两服务 demo，用 `aws_ecs_express_gateway_service` 这个
全新的 Terraform 原生资源部署。**这是迄今为止踩坑最多的一天——包括一个
真正意义上的 Terraform 依赖关系 bug，导致 destroy 卡了将近两个小时。**

## 结论先说:能用、够简单，但目前作为一个新功能，边界情况的打磨明显不够

- ✅ **确认有原生 Terraform 支持**:`aws_ecs_express_gateway_service` 是
  单一资源封装了 ECS service + ALB + target group + 安全组 + 自动扩缩容
  这一整套，这一点验证了它"和 App Runner 一样简单"的定位。
- ⚠️ **踩了四个真实的坑**,比之前任何一天都多,其中最后一个是**货真价实
  的 Terraform 依赖关系 bug**,不是"等久一点就好"的瞬时问题。
- 📊 **资源数量**:app stack 只有 **6 个 Terraform 资源**(2 个 Express
  Gateway Service + 2 个 IAM 角色 + 1 个共享集群),和 day13 的 App
  Runner(5 个)几乎打平。

## 架构

```
                 🌐 Internet
                     │
      [ caller 的 Express Mode 默认域名 *.ecs.<region>.on.aws ]
                     │
      ┌──────────────▼──────────────┐
      │  caller service               │
      │  GET /hello                   │
      │    └─ 调用 https://<callee的   │
      │       Express 域名>/data       │
      └────────────────┬───────────────┘
                        │ 普通公网 HTTPS 调用
      ┌─────────────────▼──────────────┐
      │  callee service                │
      │  也是公网可达,和 day13 一样      │  ← 和 day09-12 不同
      │  没有原生服务间鉴权              │     没有 IAM invoker
      └──────────────────────────────────┘
```

## 结构

```
day14/
├── apps/                          # 复用 day13 的 caller/callee,只改提示文字
└── terraform/
    ├── ecr/                        # 镜像仓库
    └── app/                        # 1个共享集群 + 2个IAM角色 + 2个Express服务
```

## 实测踩的四个坑

### 坑 1:provider 版本太老,压根没有这个资源类型

day08-13 一直锁的 `~> 5.0`,直接报 `Invalid resource type
"aws_ecs_express_gateway_service"`——这个资源是 2025-11 才加进 provider
的,得升到 `~> 6.0`(当前最新 6.54.0)。这一天单独锁了 6.x,没有动其它天
的 provider 版本。

### 坑 2:`cluster` 参数不会像 App Runner 那样自动帮你建

一开始以为和 App Runner 一样"给个集群名字就自动建",直接
`cluster = var.name` 结果报 `ClusterNotFoundException`。查文档才发现:
官方原话是"The ECS **default** cluster (if it does not already exist)"
会自动建——那specifically 指字面意义上叫 `default` 的集群，自定义名字的
集群必须自己先用 `aws_ecs_cluster` 建好。修法:显式加一个
`aws_ecs_cluster` 资源，和 day08-10 一贯的做法(不共用账号全局的
default 集群)保持一致。

### 坑 3:`ingress_paths[0].endpoint` 自己就带 `https://` 前缀

第一次把它拼成 `"https://${...endpoint}"`，结果 `caller_url` 输出变成
`https://https://da-xxx.ecs.us-east-1.on.aws`——caller 运行时拿这个
坏掉的 URL 去请求 callee，自然连不通。修法:去掉多余的 `https://`
前缀，直接用 `.endpoint` 本身的值。

### 坑 4(最大的一个):Terraform 在 caller 还没删完时就把它依赖的 IAM
### 权限拆掉了，导致 `terraform destroy` 卡了将近两个小时

`terraform destroy` 在等待 caller 服务从 `DRAINING` 变成 `INACTIVE` 时
超过 Terraform 内建的 20 分钟等待上限，直接报错退出。查 AWS 侧真实状态：
`desiredCount=0, runningCount=0`，但状态一直卡在 `DRAINING` 不变——一开始
以为和 day12 的 IP 释放延迟是同一类"纯粹异步、等久一点就好"的问题，
**等了将近两个小时都没有变化**，比之前见过的任何一次都久。

深挖 `aws ecs describe-services` 的 events 才找到真正的根因：

```
(service day14-caller) failed to deregister targets in (target-group ...)
with (error User: arn:aws:sts::...:assumed-role/day14-infra/ecs-service-scheduler
is not authorized to perform: elasticloadbalancing:DeregisterTargets on
resource: ... because no identity-based policy allows the
elasticloadbalancing:DeregisterTargets action)

IAM permissions policies have been misconfigured or changed, and ECS can
no longer maintain your (service day14-caller). Please reconfigure your
IAM role.
Failure Context: Role (arn:aws:iam::...:role/day14-infra) is not
authorized to perform: (elasticloadbalancing:DescribeTargetHealth).
```

再查 `aws iam list-attached-role-policies --role-name day14-infra`，
**这个角色上的托管策略已经被拆掉了(`AttachedPolicies: []`)**——但
`day14-infra` 这个角色本身还在，caller 服务当时还在积极使用这个角色
尝试把自己从 target group 里注销掉。

**根因**:`aws_ecs_express_gateway_service.caller` 和 `.callee` 两个
资源都引用了 `aws_iam_role.infrastructure`(通过 `infrastructure_role_arn`
属性),按 Terraform 常规的依赖图规则，destroy 时应该严格保证"先删完
所有引用这个角色的资源，再删角色本身"。但实测结果是：**这条依赖关系
在这次的 destroy 里没有被正确遵守**——IAM 角色策略被过早拆除，导致
caller 服务在其真正需要这个角色权限完成"从负载均衡器注销"这个异步收尾
步骤时，权限已经没了，只能不断重试、不断失败，永远卡在 `DRAINING`。
（day13 也用了同名的角色 `day13-apprunner-ecr-access`，但那次没有触发
这个问题——推测是因为 App Runner 的删除流程不涉及这种"角色仍在被
异步任务使用"的窗口期，或者窗口期短得多，没撞上。）

**修法**:手动把托管策略重新挂回角色——`aws iam attach-role-policy
--role-name day14-infra --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices`。
**重新挂上之后,caller 服务在 30 秒内就从 `DRAINING` 变成了
`INACTIVE`**——直接印证了根因判断是对的:它不是需要更久的时间,是
永远等不到,因为权限已经被拿走了，重新给回去立刻就能继续完成收尾。

**这条经验的价值**:这是本轮对比里第一次遇到"Terraform 自己的依赖图
处理出了问题"(不是配置错误,不是平台侧的异步延迟),而是并发/超时场景下
共享资源(被两个服务共同引用的 IAM 角色)的销毁顺序保护失效了。作为
一个新发布不久的资源类型(`aws_ecs_express_gateway_service` 才出现
几个月)，这类边界情况(尤其是一次 destroy 里有资源超时失败、又有另一个
资源同时在异步收尾)的健壮性明显还没打磨到位。**遇到"terraform destroy
卡住不动"时，不能默认它一定是"平台侧纯异步延迟、等着就好"——应该先去查
真实的错误事件日志，判断这到底是"需要耐心"还是"权限/依赖被破坏、永远
不会自己好"。**

## 跑起来

```bash
# 1) 镜像仓库
cd day14/terraform/ecr && terraform init && terraform apply -auto-approve

# 2) build + push
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
cd ../../apps/callee && docker build -t <repo_url>/callee:v1 . && docker push <repo_url>/callee:v1
cd ../caller && docker build -t <repo_url>/caller:v1 . && docker push <repo_url>/caller:v1

# 3) 部署(provider 需要 hashicorp/aws ~> 6.0)
cd ../../terraform/app
cp terraform.tfvars.example terraform.tfvars   # 填两个镜像地址
terraform init && terraform apply -auto-approve

# 4) 验证(部署刚完成时可能还在 canary 阶段,503 重试几次就好)
curl $(terraform output -raw caller_url)/hello

# 5) 销毁(如果 destroy 卡在 DRAINING 超过合理时间,先查 IAM 角色策略
#    有没有被过早拆掉,而不是假设是纯异步延迟)
cd app && terraform destroy -auto-approve
cd ../ecr && terraform destroy -auto-approve
# Express Mode 会自动建自己的 CloudWatch 日志组,destroy 不会清理,需要手动删:
aws logs describe-log-groups --log-group-name-prefix "/aws/ecs/<name>" \
  --query "logGroups[].logGroupName" --output text | \
  xargs -n1 -I{} aws logs delete-log-group --log-group-name {}
```

## 实测验证过的最终结果

```
Caller says hi! Called https://da-8a849d62e38640b3823f4d6b3112e8ac.ecs.us-east-1.on.aws/data
via ECS Express Mode, got back: {"from":"callee","message":"Hello from
the callee service — reached via ECS Express Mode, still no
invoker-style auth (same gap as App Runner)!"}
```

安全模型和 day13 完全一致:callee 公网可达，匿名直连 `/data` 一样能
成功——ECS Express Mode 继承了 App Runner "没有原生服务间鉴权" 这个
短板，没有解决它。

## Express Mode 该不该用？

- ✅ **值得肯定**:确认是 Terraform 原生支持(`aws_ecs_express_gateway_service`)
  而不是纯命令式 CLI 专属功能，资源数量和 App Runner 打平，建立在持续
  投入的 ECS 生态之上，长期依赖风险明显低于 App Runner。
- ⚠️ **需要注意**:作为一个刚发布几个月的新功能，实测踩坑数量是这轮
  对比里最多的一次，尤其是 destroy 阶段"权限被过早收回导致永久卡住"
  这类问题，说明边界情况处理还不够成熟。如果要在生产环境依赖它，
  建议对 destroy/更新流程做更充分的压力测试，不要假设"卡住=等等就好"。
- 依然**没有解决**服务间调用鉴权的问题——这一点上 day11(Cloud Run IAM)
  和 day12(Cloud Service Mesh)代表的 GCP side 明显领先。

## 和之前几天的关系

| | 用到/呼应的内容 |
|---|---|
| day08-10 | ECR 仓库模式、真实 ECS Fargate 基础知识复用 |
| day13 | 直接对照基准:App Runner 官方推荐的继任者,资源数量打平,服务间鉴权短板完全一致 |
| **day14(这次)** | **ECS Express Mode 实测;四个真实坑,其中一个是罕见的 Terraform 依赖关系 bug(共享 IAM 角色在依赖它的资源还没删完时被过早拆除权限);day09-14 六天的"两服务互调"系列对比至此完整收官** |
