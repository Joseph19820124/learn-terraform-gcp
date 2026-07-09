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

（后续:多环境(dev/staging/prod)、自定义 VPC …… 逐步加。）

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
