# day06 / good-practice —— 修好反模式的 GCP 版 web app

跟反面教材（AWS EC2 + httpd demo）功能对等：起一台机器，装 web server，能访问首页。
逐条修法见 [../README.md](../README.md)。

## 跑起来

```bash
cp terraform.tfvars.example terraform.tfvars   # 改 project_id
terraform init
terraform plan
terraform apply
```

apply 完直接看 `web_url` 输出，浏览器打开或 `curl` 验证。

## 想开 SSH 看看机器里面

默认不开 SSH（这是本日要讲的重点）。想开，在 `terraform.tfvars` 里加：

```hcl
ssh_source_ranges = ["你的公网IP/32"]
```

不要传 `["0.0.0.0/0"]`——那样就和反面教材犯一样的错了。

## 销毁

```bash
terraform destroy
```
