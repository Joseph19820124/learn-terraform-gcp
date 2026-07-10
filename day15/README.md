# Day 15 — Java 代码从不打日志？在 day09 基础上接 Loki + Grafana

回头看 day08–14 所有的 Spring Boot demo,会发现一个问题:**REST handler 里
只是 `return` 一个字符串,没有任何 `log.info()`**。能跑通不代表能排障——真实
系统出问题时,第一件事永远是看日志,不是看 curl 返回值。这一天在 day09 的
caller/callee 基础上做两件事:

1. **给 caller 和 callee 的代码加日志**(SLF4J,day08 起 `spring-boot-starter-web`
   已经带了,不用加依赖)。
2. **搭一个真正的日志平台**:ECS 上用 **FireLens(Fluent Bit sidecar)+ Loki**
   收日志,**Grafana** 查日志,而不是只堆在 CloudWatch 里翻。

## 结论先说:能跑通,但撞上一个和 day14 类似性质的"时序坑"——Service Connect
## 的 mesh 快照是任务启动时定的,不是实时更新的

- ✅ caller、callee 的日志都**确认**能通过 FireLens → Fluent Bit → Loki
  查询到(不是"配置对了应该能",是真的 `curl` Loki 的 `/loki/api/v1/query_range`
  拿到了日志行)。
- ⚠️ **踩了三个真实的坑**,其中最后一个是本天最大的收获——一个值得记录的
  ECS Service Connect 限制,不是配置错误。
- 📊 **资源数量**:app stack 38 个 Terraform 资源(4 个服务:caller、callee、
  loki、grafana,外加共享集群)。

## 架构

```
                 🌐 Internet
                     │
      ┌──────────────┼──────────────────┬───────────────┐
      │              │                  │               │
[caller ALB]    [grafana ALB]      [loki ALB]*      (callee 无 ALB)
      │              │                  │
┌─────▼─────┐  ┌─────▼─────┐     ┌──────▼──────┐  ┌─────────────┐
│  caller   │  │  grafana  │     │    loki     │  │   callee    │
│ log→Fluent│  │(Loki 数据源 │     │ /loki/api/  │  │ log→Fluent  │
│  Bit→Loki │  │ 已预配置)  │────▶│ v1/push,    │◀─│  Bit→Loki   │
└─────┬─────┘  └───────────┘     │ 存本地磁盘   │  └──────▲──────┘
      │ Service Connect: callee:8080          └─────────────┘
      └───────────────────────────────────────────────┘
                Service Connect: loki:3100(caller/callee/grafana 都读这个)

* loki 额外挂了公网 ALB,纯粹是为了能直接 curl 验证日志有没有进去,
  生产环境通常不会这样开。
```

- **caller / callee**:和 day09 完全一样的调用关系(caller 有 ALB,callee
  没有,只能被 Service Connect 内部访问),唯一区别是主容器的日志驱动从
  `awslogs` 换成 `awsfirelens`,任务里多一个 `log_router` sidecar。
- **loki**:官方 `grafana/loki` 镜像,零配置,单体模式,本地磁盘存储——
  短期 demo 不需要自定义配置。
- **grafana**:自定义镜像,`Dockerfile` 里把 Loki 数据源的 YAML 直接烤进
  `/etc/grafana/provisioning/datasources/`,不用登进 UI 手动配置。

## 结构

```
day15/
├── apps/
│   ├── caller/     # day09 的 caller,加了 log.info()
│   ├── callee/     # day09 的 callee,加了 log.info()
│   └── grafana/    # Dockerfile + 预配置的 Loki datasource
└── terraform/
    ├── ecr/                          # 三个镜像仓库(caller/callee/grafana)
    ├── app/                          # 根配置:1 个集群 + 4 个服务
    └── modules/
        ├── ecs-cluster/               # 和 day09 一样,原封不动
        └── ecs-fargate-service/       # day09 模块的扩展版(见下)
```

## 这一天新加的东西

### 1. FireLens + 原生 Fluent Bit `loki` output(不是社区维护的老插件)

网上大部分"ECS + Loki"教程用的是 `grafana/fluent-bit-plugin-loki` 这个
2020 年前后的社区镜像。**现在不需要了**——AWS 官方的
`public.ecr.aws/aws-observability/aws-for-fluent-bit:3` 基于 Fluent Bit
4.x,原生自带 `loki` output plugin(Fluent Bit 核心自 1.8 起就有)。配置直接
写在 FireLens 的 `options` 里:

```hcl
logConfiguration = {
  logDriver = "awsfirelens"
  options = {
    Name        = "loki"
    Host        = var.loki_host       # Service Connect 短名 "loki"
    Port        = tostring(var.loki_port)
    Labels      = "job=${var.name}"    # 每个服务一个 job 标签,方便区分
    Label_Keys  = "$container_name"
    Line_Format = "key_value"
  }
}
```

主容器还要加 `dependsOn = [{ containerName = "log_router", condition = "START" }]`,
保证 sidecar 先起来再让主容器写日志,不然日志会在 sidecar 还没准备好时丢掉。

### 2. 两个 Terraform `jsonencode` + 三元表达式的类型坑

`enable_firelens` 是个开关,同一个模块要同时支持"开"(caller/callee)和
"关"(loki/grafana 走 `awslogs`)。第一版直接写三元表达式,两次 `terraform
validate` 都报错:

- **第一次**:`main_container` 的 `dependsOn` 字段用三元表达式在"有这个
  key"和"没有这个 key"之间切换 → `Inconsistent conditional result types`
  (两个分支的 object 必须是同一组 key)。**修法**:两边都要有 `dependsOn`,
  只是关掉的时候值是空列表 `[]`,而不是不写这个 key。
- **第二次**:`container_definitions` 用三元表达式在"1 个 container"和
  "2 个 container"的列表之间切换 → tuple 长度不一致报错。**修法**:换成
  `concat([main], enable_firelens ? [log_router] : [])`,Terraform 的类型
  系统能正确处理变长列表拼接,三元表达式处理不了。

这两个都是**用 `terraform validate` 真实跑出来的报错**,不是预判出来的。

### 3. 真正的坑:ECS Service Connect 的 mesh 快照是任务启动时"定死"的

部署完成、4 个服务都 `Running = Desired`后,验证 caller 日志秒到 Loki,
**但 callee 的日志死活查不到**。查 callee 的 `log_router` sidecar 日志:

```
[warn] [net] getaddrinfo(host='loki', err=4): Domain name not found
[error] [output:loki:loki.1] no upstream connections available
```

反复重试超过 7 分钟,**一次都没成功过**——不是瞬时问题。对比两边任务的
`serviceConnectConfiguration`(通过 `aws ecs describe-service-revisions`
查),两边配置完全一样(`enabled=true`,同一个 namespace),配置本身没错。

真正原因是**任务启动的时间点**:

| 服务 | 任务 startedAt | loki 服务 createdAt |
|---|---|---|
| callee | 11:56:34 | (还不存在) |
| caller | 11:58:03 | 11:57:53 |
| loki   | 11:58:40 | — |

`callee` 的任务在 `loki` 这个 ECS 服务**被创建之前**就已经启动了——它的
Service Connect 代理(Envoy)在启动时对整个 namespace 的服务网格拍了张
"快照",那时候 `loki` 根本不存在,所以这张快照里永远没有 `loki` 这个名字,
**之后 `loki` 服务再怎么变健康、Service Connect 配置再怎么正确,这个已经
在跑的任务都不会重新去发现它**——DNS 解析会永久失败,直到这个任务被换掉。
`caller` 只是运气好,它的任务恰好在 `loki` 服务已经存在(哪怕还没
`RUNNING`)之后才启动,所以快照里带上了 `loki`。

**修法**:对已经卡住的 callee,`aws ecs update-service --force-new-deployment`
强制换一个新任务,新任务启动时 `loki` 已经存在,新快照就包含它了——换完之后
立刻验证通过。**更根本的修法**(这次没有在 Terraform 里做,值得记录):让
所有"被依赖的服务"(这里是 loki)在 Terraform 里显式 `depends_on` 排在所有
"依赖它的服务"(caller/callee/grafana)前面创建,而不是像这次这样让
`loki` 因为要读三个安全组的 output 反而变成最后创建的服务。

## 验证过程(真实跑通)

```bash
# 1. Loki 健康检查
curl $LOKI_URL/ready   # 200

# 2. 触发一轮 caller → callee 调用(应该同时触发两边打日志)
curl $CALLER_URL/hello

# 3. 查 Loki 里两边的 job 标签
curl -G "$LOKI_URL/loki/api/v1/query_range" \
  --data-urlencode 'query={job="day15-caller"}' ...
curl -G "$LOKI_URL/loki/api/v1/query_range" \
  --data-urlencode 'query={job="day15-callee"}' ...
```

第一次验证时只有 `day15-caller` 有结果,`day15-callee` 是空的——这就是上面
那个坑被发现的过程。`force-new-deployment` 之后重新触发流量,两边都能查到:

```
{"container_name":"main","job":"day15-callee",...}
  log="... INFO ... CalleeApplication : Received /data request"
  log="... INFO ... CalleeApplication : Returning response: {...}"
```

## 清理

```bash
cd terraform/app && terraform destroy -auto-approve
cd ../ecr && terraform destroy -auto-approve
```

destroy 后用 `aws ecs list-clusters` / `describe-load-balancers` /
`describe-security-groups` / `describe-log-groups --log-group-name-prefix
/ecs/day15` / `servicediscovery list-namespaces` / `ecr
describe-repositories` 逐项确认,**零残留**。FireLens sidecar 会额外产生
`awslogs-stream-prefix=firelens` 的日志流,但这些流都在同一个
`/ecs/<service>` log group 里,跟着 log group 一起删,不需要单独处理。
