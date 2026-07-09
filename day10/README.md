# Day 10 — 把 ECS Service Connect 换成 VPC Lattice，实测能不能跑通

day09 用 ECS Service Connect 让两个 ECS Fargate 服务互相调用。这一天做同一件事，
但换成 **VPC Lattice**——AWS 官方给的另一条 App Mesh 替代路径(App Mesh 2026/9/30
停服，见 day09)。**这不是纸上谈兵的方案对比，是真的写完整套 Terraform、真的部署
到 aws-10、真的调通、真的踩了坑再修好、最后真的销毁验证过的一次完整实测。**

## 结论先说:能跑通，但比 Service Connect 复杂不少，而且踩了两个真坑

- ✅ **最终跑通了**:caller 通过 VPC Lattice 生成的 DNS 名字成功调用到 callee，
  两边响应内容都验证过是最新部署的版本。
- ⚠️ **中途踩了两个真实的坑**(下面详细写)，其中一个是需要专门去查文档才能
  避开的架构级差异，不是随便试错就能碰到的。
- 📊 **资源数量对比**:day09(Service Connect)的 app stack 是 18 个资源；
  day10(Lattice)的 app stack 是 **25 个资源**——同样的"两个服务互相调用"需求，
  Lattice 版本多出 7 个资源。

## 架构

```
                 🌐 Internet
                     │
              [ caller 的 ALB ]
                     │
      ┌──────────────▼──────────────┐
      │  caller service               │
      │  GET /hello                   │
      │    └─ 调用 http://<callee的Lattice DNS名字>/data
      └────────────────┬───────────────┘
                        │  这条线走 VPC Lattice 的数据面，
                        │  不是 caller 的 ENI 直连 callee 的 ENI
      ┌─────────────────▼──────────────┐
      │  VPC Lattice Service Network    │  ← day09 没有这一层，Service Connect
      │  (day10-cluster 所在 VPC 已接入) │     直接靠 Cloud Map 命名空间
      └─────────────────┬──────────────┘
                        │
      ┌─────────────────▼──────────────┐
      │  callee service                │
      │  没有 ALB、没有公网入口          │
      │  安全组只放行 Lattice 的托管     │
      │  prefix list，不是 caller 的 SG │
      └──────────────────────────────────┘
```

## 结构

```
day10/
├── apps/                          # 和 day09 一样的两个 app，改了几句提示文字
└── terraform/
    ├── ecr/
    ├── app/                        # 根配置:1 个 ECS 集群 + 1 个 Lattice 服务网络 + 2 个服务
    └── modules/
        ├── lattice-network/        # VPC Lattice 服务网络 + VPC 关联
        └── ecs-lattice-service/    # day09 模块的 Lattice 版本
```

## 和 day09(Service Connect)的三处关键架构差异

### 1. 安全组规则完全不同 —— 这是最容易踩坑、必须查文档才知道的点

day09(Service Connect):callee 的安全组**直接引用 caller 的安全组 ID**：
```hcl
allowed_security_group_ids = [module.caller.service_security_group_id]
```
因为 Service Connect 的流量本质上还是 caller 的 ENI 直接连到 callee 的 ENI
(只是多了个本地代理帮你做 DNS 拦截和路由)。

day10(VPC Lattice):**这套写法直接失效**。AWS 文档写得很明确：
> "You can't use the client security group as a source for your target's
> security groups, because traffic flows from VPC Lattice."

VPC Lattice 的流量走的是 AWS 托管的数据面，不是 caller 的 ENI 直连。callee
的安全组必须改成引用 **AWS 托管的 prefix list**：
```hcl
data "aws_ec2_managed_prefix_list" "vpc_lattice" {
  name = "com.amazonaws.${var.region}.vpc-lattice"
}
# ingress { prefix_list_ids = [data.aws_ec2_managed_prefix_list.vpc_lattice.id] }
```
这个坑不是"跑一次报错就知道"的那种——如果按 day09 的思路直接照抄"引用调用方
安全组"，Lattice 这边**不会报错，但流量真实场景下也通不了**(本次实测提前查了
文档才避开，没有实际踩这个错误，但这恰恰说明:VPC Lattice 的安全模型需要专门
学习，不能凭直觉照搬 Service Connect 的经验)。

### 2. 需要一个专门的 IAM 角色 —— day09 完全没有的东西

ECS 要把 Fargate task 的动态 IP 自动注册进 VPC Lattice 目标组，需要一个专门的
"ECS 基础设施角色"，挂 AWS 托管策略 `AmazonECSInfrastructureRolePolicyForVpcLattice`：
```hcl
resource "aws_iam_role" "ecs_infrastructure" {
  assume_role_policy = jsonencode({
    Statement = [{ Principal = { Service = "ecs.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_infrastructure" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForVpcLattice"
}
```
这个角色通过 `aws_ecs_service` 的 `vpc_lattice_configurations.role_arn` 传进去
——这是 2024 年 11 月才加进 ECS 的原生集成能力，比较新。

### 3. 端口语义不同

day09:caller 直接调用 `http://callee:8080`(容器真实端口)。
day10:caller 调用 `http://<lattice-dns-name>`(**默认 80 端口**，Lattice 的
监听器)，Lattice 内部再转发到 callee 容器真实监听的 8080 端口。
Lattice 在架构上多了一层"监听器 → 转发规则 → 目标组"，概念上更接近 ALB，
而不是 Service Connect 那种"直接暴露容器端口"的简单模型。

## 实测中踩的坑(这次是真的踩了，不是提前避开的)

### 坑:ALB 健康检查没给 JVM 冷启动留时间，新版本部署一直失败

改完两个 app 的提示文字、重新 build+push 镜像后，重新 apply 触发 ECS 滚动更新，
结果新版本的 caller task **反复被杀、一直起不来**：
```
stoppedReason: "Task failed ELB health checks in (target-group ...)"
exitCode: 143   ← 被优雅终止，不是应用崩溃
```
根因：`aws_ecs_service` 没设 `health_check_grace_period_seconds`。Spring Boot
的 JVM 冷启动(classpath 扫描、Spring 上下文初始化)需要几秒钟，但 target group
的健康检查间隔 15 秒、连续 2 次失败就判定不健康——**容器还没来得及响应第一次
健康检查，就已经被杀了，进入"起来又被杀"的死循环**，`curl /hello` 一直返回
旧版本的响应内容(ECS 还在用还没被替换掉的旧 task 兜底)。

修法：
```hcl
resource "aws_ecs_service" "this" {
  ...
  health_check_grace_period_seconds = var.create_alb ? 60 : null
}
```
加上 60 秒宽限期后，容器有时间真正启动完成，下一次滚动更新就顺利成功了。

**这条经验同样适用于 day08、day09**——那两天因为是"首次创建服务"(没有滚动更新
这个环节)，冷启动的时间窗口被"ALB 从 0 到有 target 再到健康"的整个流程覆盖掉了，
所以没有暴露这个问题；但如果 day08/day09 的服务后续要做滚动更新(比如新版本
镜像发布)，同样会踩到这个坑。**这是这一天最有价值的收获之一。**

## 跑起来

```bash
# 1) 镜像仓库
cd day10/terraform/ecr && terraform init && terraform apply -auto-approve

# 2) build + push(两个 app 的代码在 apps/ 下)
cd ../../apps/callee && docker build -t <callee_repo_url>:v1 . && docker push <callee_repo_url>:v1
cd ../caller && docker build -t <caller_repo_url>:v1 . && docker push <caller_repo_url>:v1

# 3) 部署(1 集群 + 1 服务网络 + 2 服务)
cd ../../terraform/app
cp terraform.tfvars.example terraform.tfvars   # 填两个镜像地址
terraform init && terraform apply -auto-approve

# 4) 验证
curl http://<alb_dns_name>/hello

# 5) 销毁
cd app && terraform destroy -auto-approve
cd ../ecr && terraform destroy -auto-approve
```

## 实测验证过的最终结果

```
Caller says hi! Called http://day10-callee-012a012ecd09b563f.7d67968.vpc-lattice-svcs.us-east-1.on.aws/data
via VPC Lattice, got back: {"from":"callee","message":"Hello from the callee service —
reached via VPC Lattice, no public IP needed!"}
```

安全模型验证：
- callee 安全组入站规则**只有一条**：8080 端口，来源是 prefix list
  `pl-07cbd8b5e26960eac`(`com.amazonaws.us-east-1.vpc-lattice`)，
  **没有任何具体安全组 ID、没有 CIDR**。
- callee 有公网 IP(demo 网络没配 NAT，出网拉镜像需要)，但**外部直连这个 IP 的
  8080 端口连不上**——和 day09 的结论一致，"有公网 IP 不等于能被外部访问"。

## Service Connect vs VPC Lattice，该怎么选？

| | ECS Service Connect(day09) | VPC Lattice(day10) |
|---|---|---|
| 资源数量(2服务demo) | 18 | 25 |
| 安全组模型 | 直接引用调用方的安全组 | 必须用 AWS 托管 prefix list |
| 需要额外 IAM 角色 | 不需要 | 需要(ECS 基础设施角色) |
| 作用范围 | 单个 ECS 集群/VPC 内 | **可跨 VPC、跨 AWS 账号** |
| 适用计算类型 | 仅 ECS | ECS + EC2 + Lambda + K8s Pod + ALB 都能接 |
| 学习曲线 | 平缓，概念少 | 更陡，概念更多(网络/服务/监听器/目标组/关联) |

**结论**：如果场景就是"同一个 VPC 里几个 ECS 服务互相调用"(day09 那种)，
**Service Connect 更简单、资源更少、没有 day10 踩的这些坑**，是更好的默认选择。
**VPC Lattice 的价值在于跨边界**——跨 VPC、跨账号、甚至混合 ECS/EC2/Lambda/K8s
的场景，这些是 Service Connect 完全做不到的。这一天验证了"能不能跑通"，
答案是"能，但要为跨边界的能力多付出这些复杂度"。

## 和之前几天的关系

| | 用到/呼应的内容 |
|---|---|
| day03 | (这次没用到 import，一次成功) |
| day05/07 | 模块调用两次(caller/callee)，参数不同 |
| day08 | ECS Fargate 基础、`deregistration_delay` 教训延续 |
| day09 | 同样的两服务架构，作为直接对照基准 |
| **day10(这次)** | **VPC Lattice 实测；新增 `health_check_grace_period_seconds` 的教训，回补适用于 day08/day09** |
