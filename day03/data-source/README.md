# day03 / data source —— 引用一个现有 VPC(只读,不管理)

演示:VPC 是"别处已经建好的",我们用 **data source** 查到它,然后只在它里面建一个子网。
Terraform **从不创建/修改/删除那个 VPC**。

## 步骤

```bash
cd day03/data-source

# 1) 先用 gcloud 手工建一个 VPC,模拟"别人已经建好的现有资源"
gcloud compute networks create day03-existing-vpc \
  --subnet-mode=custom --project <你的项目ID>

# 2) 跑 Terraform(它只会创建"子网",不碰那个 VPC)
cp terraform.tfvars.example terraform.tfvars   # 改 project_id
terraform init
terraform plan     # 注意:Plan 里只有【1 个要创建】= 子网;VPC 是 data,只读不创建
terraform apply    # 输 yes
```

apply 后看 outputs:`found_existing_vpc_id` 是**查到的**现有 VPC(不是我们建的),
`created_subnet_name` 才是我们真正创建并管理的。

## 关键点:destroy 只删子网,VPC 还在

```bash
terraform destroy      # 只会删掉子网
gcloud compute networks list --project <你的项目ID>   # day03-existing-vpc 依然在!
```

因为 Terraform **从没拥有那个 VPC**(data source 只读),所以 destroy 不会碰它。
这就是 data source 的本质:**借用/查阅,不接管**。

## 收尾(手工建的 VPC 要手工删)

```bash
gcloud compute networks delete day03-existing-vpc --project <你的项目ID>
```

## 对比记忆
`network = data.google_compute_network.existing.id` ——
注意是 `data.`(数据源),不是 `google_compute_network.xxx`(资源)。
`data.` = "我查到的、别人管的";没有 `data.` 的 resource = "我建的、我管的"。
