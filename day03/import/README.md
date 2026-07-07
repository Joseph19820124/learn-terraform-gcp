# day03 / import —— 把现有 VPC 接管进 Terraform 管理

演示:VPC 是手工建的,我们用 `import {}` 块把它**接管**进 Terraform 的 state。
接管后,Terraform 就能管它了 —— 之后 `destroy` **会**删掉它。

## 步骤

```bash
cd day03/import

# 1) 先用 gcloud 手工建一个 VPC,模拟"手工/别处建的现有资源"
gcloud compute networks create day03-import-vpc \
  --subnet-mode=custom --project <你的项目ID>

# 2) 跑 Terraform:import 块会把它接管进来(不是新建)
cp terraform.tfvars.example terraform.tfvars   # 改 project_id
terraform init
terraform plan     # 会显示:1 to import(导入 1 个),而不是 1 to add(新建)
terraform apply    # 输 yes。执行后这个 VPC 就进了 Terraform 的 state
```

关键看 `plan`/`apply` 的措辞:是 **import(导入)**,不是 **create(创建)**。
apply 完再跑一次 `terraform plan`,应显示 **No changes** —— 说明代码和现实一致、已归它管。

## 证明"已归 Terraform 管":destroy 会删掉它

```bash
terraform destroy   # 这次会真的删掉 day03-import-vpc!
gcloud compute networks list --project <你的项目ID>   # 它没了
```

对比 data-source demo:那里 destroy **不会**删 VPC(因为只是引用);
这里 destroy **会**删 VPC(因为已经 import 接管、归 Terraform 所有)。

## 另一种写法:经典命令行 import(等价)

`import {}` 块是 Terraform 1.5+ 的现代写法(声明式,推荐)。老写法是命令行:

```bash
# 先写好 resource 块(不写 import 块),然后:
terraform import google_compute_network.vpc \
  projects/<你的项目ID>/global/networks/day03-import-vpc
```

两者效果一样:把现有资源塞进 state。区别是 `import {}` 块能提交进代码、可复现、可 review;
命令行是一次性操作。**新项目推荐用 `import {}` 块。**

## 一句话
import = **接管/收编**:把现有资源变成 Terraform 管的资产,以后由它改、由它删。
（对比 data source = 只读引用,永远不碰它。)
