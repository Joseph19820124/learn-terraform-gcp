# learn-terraform-gcp

从零开始、循序渐进地学 **Terraform**,每天一个能真正跑起来的小 demo(以 **GCP** 为例)。

每个 `dayNN/` 目录都是**独立、可直接运行**的:clone 下来,进对应目录,按里面的 README 跑 `init / plan / apply` 就能在 GCP 上真正创建资源。

## 目录

| 天 | 主题 | 你会创建 |
|---|---|---|
| [day01](day01/) | Terraform 入门 + 第一个资源 | 一个 GCP **VPC 网络** |

（后续:day02 子网、day03 防火墙/实例、模块化、远程 state …… 逐步加。）

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
