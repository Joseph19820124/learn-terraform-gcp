# Day 01 — 用 Terraform 创建你的第一个 GCP 资源:一个 VPC

目标:**跑通完整流程,在 GCP 上真正创建一个 VPC 网络**,并理解 Terraform 的基本用法。

## 这一天你会学到

- Terraform 的三步核心命令:`init` → `plan` → `apply`
- provider / resource / variable / output 各是什么
- 怎么安全地销毁(`destroy`),避免留下资源

---

## 一、准备工作(只需做一次)

1. **装 Terraform**(1.3+):https://developer.hashicorp.com/terraform/install
   验证:`terraform version`

2. **装 gcloud CLI** 并登录:https://cloud.google.com/sdk/docs/install
   ```bash
   gcloud auth login
   ```

3. **有一个开了结算(billing)的 GCP 项目**。查看当前项目 ID:
   ```bash
   gcloud config get-value project
   ```

4. **让 Terraform 能用你的身份**(这一步最关键,叫 ADC —— 应用默认凭证):
   ```bash
   gcloud auth application-default login
   ```
   跑完 Terraform 就会自动用你的账号去操作 GCP,不用在代码里写密钥。

5. **打开 Compute Engine API**(创建 VPC 需要它,`<项目ID>` 换成你的):
   ```bash
   gcloud services enable compute.googleapis.com --project <项目ID>
   ```

---

## 二、跑起来(每次的正式流程)

```bash
cd day01

# 1) 复制变量样例,填上你自己的项目 ID
cp terraform.tfvars.example terraform.tfvars
#    然后用编辑器打开 terraform.tfvars,把 project_id 改成你的项目 ID

# 2) init:下载 google provider、初始化工作目录(第一次必须做)
terraform init

# 3) plan:预演,看看 Terraform 打算创建什么(不会真的动 GCP)
terraform plan

# 4) apply:真正执行,创建 VPC。它会再给你看一遍计划,输入 yes 确认
terraform apply
```

apply 成功后,终端会打印 outputs(vpc_name / vpc_id / vpc_self_link)。

---

## 三、验证(确认 GCP 上真建出来了)

```bash
gcloud compute networks list --project <项目ID>
```
你应该能看到名为 `my-first-vpc` 的网络。也可以去 GCP 控制台 → VPC network 里看。

---

## 四、销毁(学完记得删,避免留资源)

```bash
terraform destroy
```
输入 `yes` 确认。它会把这次创建的 VPC 删掉,回到干净状态。
（VPC 本身不收费,但养成"用完即删"的好习惯。）

---

## 五、文件说明

| 文件 | 作用 |
|---|---|
| `main.tf` | 主代码:声明 provider(GCP)+ 要创建的 resource(VPC) |
| `variables.tf` | 定义变量(project_id / region / vpc_name),把可变的值抽出来 |
| `outputs.tf` | apply 后要打印的信息 |
| `terraform.tfvars.example` | 变量值的样例;复制成 `terraform.tfvars` 填你自己的值 |
| `.terraform.lock.hcl` | 依赖版本锁定文件(init 生成,**应提交到 git**) |

---

## 常见问题

- **`Error 403 ... Compute Engine API has not been used`** → 第一步的 API 没开,回去跑 `gcloud services enable compute.googleapis.com`。
- **`Error: google: could not find default credentials`** → 没做 `gcloud auth application-default login`。
- **`project_id` 报错必填** → 你没建 `terraform.tfvars` 或没填 project_id。

下一天(day02)会在这个 VPC 里加子网(subnet)。
