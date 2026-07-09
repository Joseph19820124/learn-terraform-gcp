# Day 09 — 两个 ECS 服务互相调用:ECS Service Connect 实战

day08 部署了单个 ECS Fargate 服务。这一天问的问题是：**如果有两个服务需要互相
调用，要不要上 service mesh？** 先说结论：**AWS App Mesh 不推荐**——它已经在被
淘汰(新客户从 2024/9/24 起无法接入，**2026/9/30 全面停止支持**，离这个仓库写
的时间只剩不到 3 个月)，AWS 官方给的替代路径是 **ECS Service Connect / VPC
Lattice / 直接走 ALB**。这一天用 **ECS Service Connect** 实现"两个服务互相
调用"，比完整的 Envoy mesh 轻量很多，而且是 ECS 原生能力，不用额外装 sidecar
基础设施。

## 架构

```
                 🌐 Internet
                     │
              [ caller 的 ALB ]  ← 唯一公网入口
                     │
      ┌──────────────▼──────────────┐   ECS Cluster "day09-cluster"
      │  caller service              │   (共享一个 Service Connect 命名空间)
      │  GET /hello                  │
      │    └─ 调用 http://callee:8080/data ──┐
      └───────────────────────────────┘      │  这条线走 ECS Service Connect，
                                              │  不是公网、不用 ALB
      ┌───────────────────────────────┐      │
      │  callee service               │◄─────┘
      │  没有 ALB、没有公网入口         │
      │  GET /data                    │
      └────────────────────────────────┘
```

- **caller**:对外挂 ALB，`/hello` 会转身调用 callee，把 callee 的响应一起返回，
  用来证明调用链真的打通了。
- **callee**:**没有 ALB**，只能被同一个 Service Connect 命名空间里的服务用短
  名字 `callee` 访问；安全组只放行来自 caller 安全组的流量，没有 `0.0.0.0/0`。

## 结构

```
day09/
├── apps/
│   ├── caller/    # 对外服务，/hello 里发起对 callee 的调用
│   └── callee/    # 纯内部服务，/data 返回一句话
└── terraform/
    ├── ecr/                          # 两个镜像仓库(独立生命周期)
    ├── app/                          # 根配置:1 个集群 + 2 个服务
    └── modules/
        ├── ecs-cluster/               # 共享集群 + Service Connect 命名空间
        └── ecs-fargate-service/       # day08 模块的扩展版(见下)
```

## 这一天新加的东西(相对 day08 模块的三处扩展)

### 1. ALB 变成可选的(`create_alb`)

day08 的模块每次调用都会建一个 ALB。这一天 `callee` 传 `create_alb = false`，
模块内部用 Terraform 的 `count` 让 ALB、监听器、目标组、ALB 安全组**整条链路
都不创建**。没有 ALB 就没有公网入口——这是"内部服务默认不暴露"的最直接实现。

### 2. ECS Service Connect 配置

```hcl
service_connect_configuration {
  enabled   = var.enable_service_connect
  namespace = var.namespace_arn

  dynamic "service" {
    for_each = var.service_connect_name != "" ? [1] : []
    content {
      port_name      = var.container_port_name
      discovery_name = var.service_connect_name
      client_alias {
        port     = var.container_port
        dns_name = var.service_connect_name
      }
    }
  }
}
```

关键点：**所有服务都要 `enabled = true`**(这样它们才能"发起"对其他 Service
Connect 服务的调用)，但**只有想被按名字调用的服务**(这里是 callee)才声明
`service {}` 块。caller 不声明——它不需要被谁调用。

### 3. 精细的安全组访问控制(`allowed_security_group_ids`)

day06/day08 的安全组只有"对全世界开放"或"不开放"两档。这一天加了第三档：

```hcl
module "callee" {
  ...
  allowed_security_group_ids = [module.caller.service_security_group_id]
}
```

callee 的安全组入站规则**只认 caller 的安全组 ID**，不是 CIDR。这是比"开一个
IP 段"更精确的访问控制——即使 caller 的 IP 变了(比如任务重建)，这条规则永远
自动跟着 caller 的安全组走，不用手动更新。

## 跑起来

```bash
# 1) 两个镜像仓库
cd day09/terraform/ecr
terraform init && terraform apply -auto-approve
# 记下 repository_urls 里的两个地址

# 2) build + push 两个镜像
cd ../../apps/callee
docker build -t <callee_repo_url>:v1 .
docker push <callee_repo_url>:v1
cd ../caller
docker build -t <caller_repo_url>:v1 .
docker push <caller_repo_url>:v1

# 3) 部署(集群 + 两个服务)
cd ../../terraform/app
cp terraform.tfvars.example terraform.tfvars   # 填两个镜像地址
terraform init && terraform apply -auto-approve
# 输出 caller_web_url

# 4) 验证 —— 这一步在证明"caller 真的能通过内部名字调用到 callee"
curl http://<alb_dns_name>/hello
# 应该看到 caller 自己的话 + callee 返回的 JSON 拼在一起

# 5) 销毁
cd app && terraform destroy -auto-approve
cd ../ecr && terraform destroy -auto-approve
```

## 实测验证过的关键结果

真跑在 aws-10 上，`curl /hello` 返回：
```
Caller says hi! Called http://callee:8080/data via ECS Service Connect,
got back: {"from":"callee","message":"Hello from the callee service —
reached via ECS Service Connect, no public IP needed!"}
```
——caller 收到了 callee 的真实响应，证明跨服务调用链路是通的。

同时验证了"安全"这一半：
- `aws ecs describe-services` 显示两个服务都 `ACTIVE`，`1/1 running`。
- callee 的安全组**只有一条入站规则**：8080 端口，来源是 caller 的安全组 ID，
  **没有任何 `0.0.0.0/0`**。
- callee 其实也有一个公网 IP(这个 demo 用 default VPC 的公有子网、没配 NAT，
  所有 task 都需要公网 IP 才能出网拉镜像)，但**直接从外部 curl 这个 IP 会连不上**
  ——这正好证明了"有公网 IP 不等于能被外部访问"，真正挡住外部访问的是安全组。

## 沿用 day08 的教训，这次提前修了一处

day08 的 `destroy` 在 ECS service 那步卡了 5-6 分钟，原因是 ALB 目标组默认
300 秒的 deregistration delay。这一天在模块里把它设成 30 秒：
```hcl
resource "aws_lb_target_group" "this" {
  ...
  deregistration_delay = 30
}
```
实测这次的 destroy 明显快很多——**这是 day08 学到的教训被直接应用到了新代码里**，
学习案例调这个参数没问题，生产环境的取舍需要重新权衡(缩短这个窗口意味着正在
处理的请求被中断的概率变高)。

## 和之前几天的关系

| | 用到的概念 |
|---|---|
| day03 | (这次没用到 import，但上次 day08 用了——这次没被打断，一次成功) |
| day05 / day07 | 模块化、模块调用多次 —— 这次是同一个模块调用两次，参数不同(有无 ALB、有无 service_connect_name) |
| day08 | ECS Fargate 基础、ECR 独立生命周期、deregistration_delay 的教训 |
| **day09(这次)** | **多服务架构下的服务发现与访问控制**：Service Connect + 精细化安全组 |

## 一句话总结

> 两个 ECS Fargate 服务互相调用，不需要完整的 service mesh(尤其 App Mesh
> 已经在 2026 年被 AWS 淘汰)。**ECS Service Connect 用一个 Cloud Map 命名空间
> + 服务级别的声明式配置，就能做到"按名字互相发现、按安全组精确控制谁能访问
> 谁"**——这在 Terraform 里就是 `service_connect_configuration` 这一个 block
> 的事，没有额外的 sidecar 基础设施要维护。
