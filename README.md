# learn-terraform-gcp

从零开始、循序渐进地学 **Terraform**,每天一个能真正跑起来的小 demo(以 **GCP** 为例)。

每个 `dayNN/` 目录都是**独立、可直接运行**的:clone 下来,进对应目录,按里面的 README 跑 `init / plan / apply` 就能在 GCP 上真正创建资源。

## 目录

| 天 | 主题 | 你会创建 |
|---|---|---|
| [day01](day01/) | Terraform 入门 + 第一个资源 | 一个 GCP **VPC 网络** |
| [day02](day02/) | 资源引用 + 自动依赖排序 | **VPC + 子网(subnet)** |
| [day03](day03/) | 用上现有资源:**data source vs import** 及区别 | 引用/接管现有 VPC |
| [day04](day04/) | **远程 state**:把 state 存到 GCS(团队协作 + 加锁) | VPC(state 在 GCS) |
| [day05](day05/) | **module 模块化**:封装可复用模块,调用多次 | 一份模块 → 两套 VPC+子网 |
| [day06](day06/) | **常见反模式对照**(真实案例)+ 修好的 GCP 版 web app | VM + web server(nginx,可访问首页) |
| [day07](day07/) | 把 day06 的安全基线**封装成模块**,调用两次 | 一份模块 → 两台"team-a/b"web 服务器 |
| [day08](day08/) | **真实案例重构**:Serverless Framework → Terraform(切到 **AWS** ECS Fargate) | Spring Boot app 跑在 ECS Fargate + ALB + 自动扩缩容 |
| [day09](day09/) | 两个服务互相调用:**ECS Service Connect**(App Mesh 2026/9/30 停服，官方替代方案) | caller(有ALB) 调用 callee(纯内部，无公网) |
| [day10](day10/) | 同样两服务架构换成 **VPC Lattice** 实测:能跑通，但比 Service Connect 多 7 个资源、多两个真坑 | 25个资源 vs day09 的18个；含安全组模型/IAM角色/健康检查宽限期的对比 |
| [day11](day11/) | 同样"两服务互调"需求换回 **GCP Cloud Run + IAM** 原生认证:不需要 service mesh | 只需 6 个资源；隔离层从网络变成身份，含 IAM 传播延迟的真实坑 |
| [day12](day12/) | 同样两服务架构接上 **Cloud Service Mesh**(day10 VPC Lattice 的 GCP 对照，目前 Preview) | 16 个资源 vs day11 的 6 个；Envoy sidecar 自动接管认证，实测三个坑(Beta provider、mesh 依赖传播延迟、Direct VPC egress 释放延迟) |
| [day13](day13/) | 切回 AWS 实测 **App Runner**(Cloud Run 的 AWS 对应物，2026-04-30 起已停止对新客户开放) | 5 个资源；callee 完全没有调用方限制(App Runner 没有 IAM invoker 概念)；caller 首次创建失败重试即成功 |
| [day14](day14/) | 实测 App Runner 官方推荐继任者 **ECS Express Mode**(全新 Terraform 原生资源) | 6 个资源；踩坑最多的一天，含一次真正的 Terraform 依赖关系 bug(共享 IAM 角色权限被过早收回，destroy 卡近 2 小时) |
| [day15](day15/) | day08–14 的 Java 代码从没打过日志——在 day09 基础上接 **FireLens + Loki + Grafana** | 38 个资源；caller/callee 日志确认查得到；踩到 ECS Service Connect 的 mesh 快照只在任务启动时拍一次、不会实时更新的坑 |
| [day16](day16/) | 在 day15 基础上把 Spring Boot 从 `3.3.4` 升到 **`4.1.0`**(2026-06-10 GA) | 应用代码零改动(`RestClient` 早在 day09 就用上了，不是 4.1 新东西)；只提了 Gradle/JDK 工具链版本；提前用 day15 学到的 `force-new-deployment` 规避了 Service Connect 的坑 |

（day01–07 是 GCP;day08–10 引入 AWS 案例做对比;day11–12 回到 GCP，分别用 Cloud Run 原生 IAM 和 Cloud Service Mesh 对照 day09/10;day13–14 切回 AWS，实测 App Runner 和它的继任者 ECS Express Mode。day09-14 六天"两服务互调"系列对比至此收官。day15 回头补上 day08 起就缺失的应用日志，接了 Loki + Grafana；day16 把 day15 升级到 Spring Boot 4.1.x。后续:多环境(dev/staging/prod)、自定义 VPC …… 逐步加。）

## 快速开始

```bash
git clone https://github.com/Joseph19820124/learn-terraform-gcp.git
cd learn-terraform-gcp/day01
# 按 day01/README.md 的步骤操作
```

## 前置要求(一次性)

- 装 [Terraform](https://developer.hashicorp.com/terraform/install)(1.3+)和 [gcloud CLI](https://cloud.google.com/sdk/docs/install)
- 一个开了 billing 的 GCP 项目
- 登录并设置应用默认凭证:
  ```bash
  gcloud auth login
  gcloud auth application-default login
  ```

详见每天目录里的 README。
