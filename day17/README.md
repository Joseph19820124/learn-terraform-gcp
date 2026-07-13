# Day 17 — 用 Traefik 替代 ALB 的路由决策:在 day09 基础上改造 ingress

day09 的 ingress 很简单:一个 ALB,一个 target group,一条 listener 规则,
把所有流量原样转发给 caller,没有任何 L7 智能。这一天想验证:**能不能把
"该转发给谁"这个路由决策从 ALB(写死的 target group/listener)挪到
Traefik(读 ECS API 动态发现服务、按 label 生成路由规则)？**

## 结论先说:能,但没有 100% 甩掉 AWS 自己的负载均衡器,而且过程中撞上了
## 一个账号级别的真实门槛,以及 day15 那个 Service Connect 坑的第二次现身

- ✅ **caller 不再有自己的 ALB/target group**——这个事实由 Terraform output
  `caller_has_no_own_alb` 和 AWS CLI 独立验证(`describe-target-groups`
  查不到任何 `day17-caller-*`)。路由到 caller 完全靠 Traefik 读它的
  `dockerLabels` 动态发现。
- ⚠️ **原计划(NLB + Traefik)被账号级别的信任审核拦住了**,真实撞见,不是
  猜的——见下面"踩的坑"第一条。改成了 ALB + Traefik。
- ⚠️ **day15 发现的 ECS Service Connect mesh 快照坑,在这里复现了一次**——
  caller 的任务在 callee 的 Service Connect 注册完成前就启动,DNS 解析
  `callee` 永久失败,直到 force-new-deployment。

## 架构:对比 day09

```
day09:  Internet → ALB(target group 写死指向 caller)→ caller → (Service
                    Connect) → callee

day17:  Internet → ALB(只做入口/健康检查，不知道 caller 是谁)
                    → Traefik(轮询 ECS API,读 caller 的 dockerLabels,
                      动态生成路由规则)→ caller → (Service Connect,不变)
                      → callee
```

caller 唯一的变化:`create_alb = false`,加了三个 `dockerLabels`:

```hcl
docker_labels = {
  "traefik.enable"                                        = "true"
  "traefik.http.routers.caller.rule"                      = "PathPrefix(`/`)"
  "traefik.http.services.caller.loadbalancer.server.port" = "8080"
}
```

callee 完全不变——没有 `traefik.enable` 标签,Traefik 的 `exposedByDefault
= false` 意味着它默认不代理任何服务,callee 从 Traefik 这条路也访问不到,
和 day09 的结论一样。

## 这一天新加的模块能力

`ecs-fargate-service` 模块加了一个 `docker_labels` 变量(`map(string)`,
默认 `{}`),直接透传进容器定义的 `dockerLabels` 字段——这是 day09 模块
没有的东西,因为 day09 从没需要过给容器打 Docker 风格的 label。

## 踩的坑

### 1. NLB 创建被账号级别拦住(真实撞见)

最初设计是 Internet → **NLB**(纯 L4 转发)→ Traefik。真实 `terraform
apply` 时,`aws_lb`(`load_balancer_type = "network"`)创建直接报错:

```
Error: creating ELBv2 network Load Balancer (day17-traefik-nlb):
OperationNotPermitted: This AWS account currently does not support
creating load balancers. For more information, please contact AWS Support.
```

查了一圈(不是瞎猜,查了 `service-quotas` 和 AWS 社区案例):**不是配额
问题**——`Network Load Balancers per Region` 配额显示 50,一个没用。这是
AWS 对"这个账号第一次创建某种类型的负载均衡器"的自动信任审核,和这个
账号已经成功建过一堆 ALB(day08 到 day16 都用过)是两码事——ALB 和 NLB
的审核是分开走的。账号没有 Support 订阅(`aws support` 系列 API 直接报
`SubscriptionRequiredException`),没法用 CLI 开工单申请人工解除。

**改法**:Internet → **ALB**(只做入口和健康检查,不写死任何路由规则)
→ Traefik → caller。核心教学点(Traefik 动态路由替代写死的 target
group)完全不受影响,只是多了一层 AWS 自己的负载均衡器,没有做到
"100% 用 Traefik 取代所有 AWS 原生负载均衡"。

### 2. day15 的 Service Connect mesh 快照坑，第二次真实复现

部署完成、三个 ECS 服务都 `Running = Desired` 后,第一次 `curl
$TRAEFIK_URL/hello` 返回 `500`,caller 的 CloudWatch 日志显示:

```
java.nio.channels.UnresolvedAddressException: null
    at java.base/sun.nio.ch.Net.checkAddress(...)
    ...
```

和 day15 一模一样的根因:caller 的任务比 callee 的 Service Connect
注册更早启动,它的 Envoy 代理对整个 namespace 拍的"服务网格快照"里压根
没有 `callee` 这个名字,DNS 永久解析失败。这一次不是"忘了"这个坑——是
day17 直接从 day09 复制过来的两服务并行创建的 apply 顺序,天然就有这个
时序竞争,没有主动像 day16 那样提前 force-new-deployment 规避,所以真实
撞上了一次。

**修法**:和 day15 一样,`aws ecs update-service --cluster day17-cluster
--service day17-caller --force-new-deployment`,等它重新稳定,再验证——
一次通过。

## 验证

```bash
TRAEFIK_URL="http://<traefik-alb-dns-name>"

# 全链路：ALB → Traefik → caller → Service Connect → callee
curl $TRAEFIK_URL/hello
# Caller says hi! Called http://callee:8080/data via ECS Service Connect,
# got back: {"from":"callee","message":"Hello from the callee service..."}

# callee 从 Traefik 这条路也访问不到(没打 traefik.enable 标签)
curl -o /dev/null -w "%{http_code}" $TRAEFIK_URL/data   # 404

# 独立确认 caller 没有自己的 target group
aws elbv2 describe-target-groups \
  --query 'TargetGroups[?contains(TargetGroupName, `day17-caller`)]'
# 空

# Traefik 日志确认它真的启动了 ECS provider(默认日志级别是 ERROR，
# 什么都看不到，这一天显式加了 --log.level=INFO)
# "Starting provider *ecs.Provider"，之后没有报错
```

## 清理

```bash
cd terraform/app && terraform destroy -auto-approve
cd ../ecr && terraform destroy -auto-approve
```

destroy 后用 `aws ecs list-clusters` / `describe-load-balancers` /
`describe-target-groups` / `describe-security-groups` /
`describe-log-groups --log-group-name-prefix /ecs/day17` /
`servicediscovery list-namespaces` / `ecr describe-repositories` 逐项
确认,**零残留**(app stack 26 个资源,ecr stack 2 个)。
