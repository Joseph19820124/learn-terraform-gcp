# Day 16 — 升级到 Spring Boot 4.1.x:架构不变，只换版本号，仍然踩了坑

day08 起所有 Spring Boot demo 都钉死在 `3.3.4`。这一天问的问题很直接:
**Spring Boot 4.1.x 现在真的能用吗？** 先查证:**Spring Boot 4.1.0 已于
2026-06-10 正式 GA**(Spring Framework 7.0.8,最低要求 Java 17,官方推荐
Java 25 这条最新 LTS)。这一天原样照抄 day15 的 caller/callee/Loki/Grafana
架构,只把 Spring Boot 版本从 `3.3.4` 升到 `4.1.0`,验证真实的升级成本。

## 结论先说:代码几乎不用改，工具链要跟着提，Service Connect 的坑提前防住了

- ✅ **`RestClient` 早就有了**,不是 4.1 的新东西——`day09` 起 caller 就在用
  `org.springframework.web.client.RestClient`(Spring Framework 6.1 / Boot
  3.2 引入的)。用户最初以为这次升级要"换成 RestClient",实际上这部分
  升级前就已经完成,这一天验证的纯粹是版本号本身。
- ⚠️ **应用代码零改动**:`CallerApplication.java` / `CalleeApplication.java`
  和 day15 一字不差,只有 `build.gradle` 和 `Dockerfile` 变了。
- ⚠️ **工具链跟着 Spring Boot 4.1 的最低要求提了三处**(见下)。
- ✅ **提前防住了 day15 踩过的 Service Connect 坑**:这次部署完成后没有
  直接验证,而是先对 caller/callee 做了一次 `force-new-deployment`,再
  验证——一次就通过,两边日志都查得到,没有重复 day15 那次"7 分钟 DNS
  解析不出来"的调试过程。

## 这一天改了什么(相对 day15)

| | day15 | day16 |
|---|---|---|
| Spring Boot | `3.3.4` | `4.1.0` |
| `io.spring.dependency-management` | `1.1.6` | `1.1.7`(配合 4.1 验证过的版本) |
| `sourceCompatibility` | `17` | `21` |
| 构建镜像 | `gradle:8.10-jdk17` | `gradle:8.14-jdk21`(Spring Boot 4.1 最低要求 Gradle 8.14) |
| 运行时镜像 | `eclipse-temurin:17-jre-alpine` | `eclipse-temurin:21-jre-alpine` |
| 应用代码 | — | **零改动**,和 day15 完全一样 |
| Terraform | — | **零改动**,和 day15 完全一样(只是把 `day15` 换成 `day16`) |

Gradle 版本是唯一一处"不提就跑不起来"的地方——`gradle:8.10` 构建
Spring Boot 4.1.0 项目时,Spring Boot Gradle 插件会在 `dependencies`
解析阶段直接报最低 Gradle 版本要求不满足,查 Spring Boot 4.1 的
system-requirements 文档确认了这一点:**最低 Gradle 8.14(8.x 分支)或
Gradle 9**。sourceCompatibility 从 17 提到 21 不是必须的(4.1 最低仍是
Java 17),纯粹是跟着官方"推荐用最新 LTS"的建议顺手提了一格。

## 本地验证(踩坑之前先在本地过一遍)

Docker 里跑通了才推去 AWS,省了一次真实部署失败的成本:

```bash
docker run -d --name callee-c ... day16-callee-test:local
docker run -d --name caller-c -e CALLEE_URL=http://callee-c:8080 ... day16-caller-test:local
curl http://localhost:18080/hello
# Caller says hi! ... got back: {"from":"callee","message":"Hello from the callee service..."}
```

两边容器日志都打出了 `:: Spring Boot ::  (v4.1.0)` 的启动横幅,
`Starting CallerApplication ... using Java 21.0.11`——确认镜像里跑的
就是升级后的版本,不是缓存了旧的构建产物。本地验证也顺带确认了 Spring
Boot 4.1 新加的 HTTP 客户端 SSRF 缓解(`InetAddressFilter`,默认会不会
拦截访问私有地址段的出站请求)**没有默认拦掉** caller → callee 这种走
容器内部私网地址的调用——如果默认拦截,这个本地测试就直接会在
`RestClient` 请求阶段报错,而不是等到部署上 AWS 才发现。

## 真实部署验证

架构和 day15 完全一样(见 [day15/README.md](../day15/README.md) 的架构图),
这里不重复画。部署完成后:

```bash
# 学到 day15 的教训:loki 服务因为要读 caller/callee/grafana 三个安全组的
# output,在 Terraform apply 里总是最后创建的；caller/callee 的任务如果
# 在 loki 存在之前就启动，它们的 Service Connect 代理拍的 mesh 快照里
# 永远不会有 loki，DNS 会永久解析失败。这次不等着踩这个坑，
# 部署完直接强制两边换一次新任务：
aws ecs update-service --cluster day16-cluster --service day16-callee --force-new-deployment
aws ecs update-service --cluster day16-cluster --service day16-caller  --force-new-deployment
aws ecs wait services-stable --cluster day16-cluster --services day16-caller day16-callee

curl $CALLER_URL/hello   # 触发一轮调用
curl "$LOKI_URL/loki/api/v1/label/job/values"
# {"status":"success","data":["day16-callee","day16-caller"]}
```

两个 job 标签一次性都出现,没有再出现 day15 那种"caller 有、callee 没有"
的分裂结果——Service Connect 那个坑是任务启动时序问题,不是配置问题,
提前换一次任务就能规避,不需要改 Terraform。

## 清理

```bash
cd terraform/app && terraform destroy -auto-approve
cd ../ecr && terraform destroy -auto-approve
```

destroy 后用 `aws ecs list-clusters` / `describe-load-balancers` /
`describe-security-groups` / `describe-log-groups --log-group-name-prefix
/ecs/day16` / `servicediscovery list-namespaces` / `ecr
describe-repositories` 逐项确认,**零残留**,和 day15 一样干净。
