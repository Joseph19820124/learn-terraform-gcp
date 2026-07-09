# Day 08 — 真实案例重构:从 Serverless Framework 迁到 Terraform(AWS ECS Fargate)

背景:review 过一个真实的生产微服务代码(Nike 内部 Spring Boot 服务，部署在
ECS Fargate 上)，它用 **Serverless Framework + 私有内部插件**
(`@nike/fibers-serverless-ecs-fargate-plugin`)做 IaC。这一天做一次**同构重构**
练习:写一个最小 Spring Boot app，先展示"原来的做法"长什么样，
再用**纯 Terraform**重新实现一遍等价的基础设施，**真部署、真验证、真销毁**。

> ⚠️ 这不是那个真实 Nike 服务的代码，是按同样的架构思路(ECS Fargate + ALB +
> Application Auto Scaling)重新写的通用学习案例，用的是标准公开的
> Terraform AWS provider，不涉及任何私有代码/内部系统。

## 结构

```
day08/
├── app/                      # 最小 Spring Boot app(/health + /hello)
│   ├── Dockerfile
│   ├── build.gradle
│   └── src/main/java/...
├── serverless-original/      # "原来的做法"参考(仅供对照阅读，不会真的部署)
│   └── serverless.yml
└── terraform/                # 这一天的主角:重构成 Terraform
    ├── ecr/                    # 镜像仓库(独立生命周期，先 apply)
    ├── app/                    # 根配置:调用模块，部署到 ECS Fargate
    └── modules/
        └── ecs-fargate-service/  # 可复用模块:ECS+ALB+AutoScaling
```

## 核心对比:Serverless Framework(黑盒抽象) vs Terraform(显式资源)

`serverless-original/serverless.yml` 里，`fargate:` 这几行"看起来"很简单：

```yaml
fargate:
  ecs:
    cpu: 256
    memory: 512
  autoScale:
    metric: ECSServiceAverageCPUUtilization
    targetValue: 50
    min: 1
    max: 3
  alb:
    healthCheckPath: /health
```

但背后私有插件要把这几行**展开成一整套 CloudFormation 资源**——ECS
TaskDefinition、Service、ALB、TargetGroup、Listener、IAM 角色绑定、
ApplicationAutoScaling 的 Target 和 Policy、CloudWatch 日志组……你在这份
YAML 里**一个都看不到**，是插件内部的黑盒逻辑。

`terraform/modules/ecs-fargate-service/main.tf` 用标准 AWS provider
资源把同样的架构**逐一显式写出来**——大约 130 行 HCL，对应了：

| Serverless 插件隐式生成的 | Terraform 里显式对应的资源 |
|---|---|
| ECS 集群 | `aws_ecs_cluster` |
| Task 定义 | `aws_ecs_task_definition` |
| ECS Service | `aws_ecs_service` |
| ALB + 监听器 + 目标组 | `aws_lb` / `aws_lb_listener` / `aws_lb_target_group` |
| 安全组 | `aws_security_group`(ALB 一个、task 一个，分开) |
| Task 执行角色 | `aws_iam_role` + `aws_iam_role_policy_attachment` |
| 自动扩缩容 | `aws_appautoscaling_target` + `aws_appautoscaling_policy` |
| CloudWatch 日志组 | `aws_cloudwatch_log_group` |

**这就是这次重构练习真正的价值**：不是"哪个工具更好"，而是
**用 Terraform 写完这一遍之后，你能看懂并解释每一个资源是干什么的**——
而 Serverless + 私有插件那条路径上，这些细节被插件封装吃掉了。

## 跑起来(五步，和真实生产流程一致的顺序)

```bash
# 1) 先建镜像仓库(独立 stack，长期存在)
cd day08/terraform/ecr
terraform init
terraform apply -auto-approve
# 记下输出的 repository_url

# 2) build + push 镜像
cd ../../app
docker build -t <repository_url>:v1 .
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <ECR注册表地址>
docker push <repository_url>:v1

# 3) 部署 ECS Fargate(计算层，跟着镜像 tag 走)
cd ../terraform/app
cp terraform.tfvars.example terraform.tfvars   # 填入 container_image
terraform init
terraform apply -auto-approve
# 输出 web_url

# 4) 验证(ECS task 启动 + ALB 健康检查通过要 1-2 分钟)
curl http://<alb_dns_name>/hello
curl http://<alb_dns_name>/health

# 5) 用完销毁(注意顺序:先 app 后 ecr)
cd ../app && terraform destroy -auto-approve
cd ../ecr && terraform destroy -auto-approve
```

## 实测过程中遇到的坑(都是真踩的，不是编的)

### 1. `terraform apply` 超时被打断 → 资源"孤儿化"

第一次 apply 因为等 ECS service 达到稳定状态耗时较长，执行环境把进程中断了。
**ALB 其实已经在 AWS 上建出来了，但 Terraform 还没来得及把这个事实写回 state**
——变成了"云上有、state 不知道"的孤儿资源。重新 apply 直接报错：
```
Error: ELBv2 Load Balancer (day08-hello-fargate-alb) already exists
```
解决办法正是 **day03 学的 `terraform import`**：
```bash
terraform import module.web.aws_lb.this <ALB的ARN>
```
把这个已存在的 ALB"认领"进 state，再继续 apply 剩下的资源。
**这是 day03 概念在真实场景里的直接应用**——概念课不是白学的。

### 2. `terraform destroy` 在 ECS service 这步卡了 5-6 分钟

不是卡住了，是**正常等待**：ALB Target Group 有个默认 300 秒的
**deregistration delay**(注销延迟)——ECS service 缩容到 0 时，ALB 要等
这个时间窗口，确保正在处理中的请求优雅结束，才会真正解绑这个 target。
`aws_ecs_service` 的 destroy 会一直等到这个过程完成。**这是预期行为，
不是 bug**，生产环境这个延迟是为了不中断正在处理的用户请求，学习环境
如果想更快销毁，可以给 target group 加
`deregistration_delay = 30`(秒)之类的更短配置。

## 一句话总结

> **Serverless Framework + 私有插件**用一份短小的 YAML 换来"快"，代价是
> 具体资源被插件黑盒吃掉，团队高度依赖这个插件的维护者。
> **Terraform** 用更多行数换来"看得见、改得动、审得了"，每个资源、
> 每条安全组规则、每个 IAM 绑定都在你的代码里，可以 `git diff`、
> 可以 code review、可以离开这个内部插件独立存在。
> 两者都能达到同一个基础设施目标，差别在于**抽象层级放哪**——
> 是放在团队共享的黑盒插件里，还是放在每个人都能读懂的显式代码里。
