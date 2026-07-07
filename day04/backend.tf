# backend.tf —— 把 state 存到 GCS(远程),而不是本地的 terraform.tfstate 文件。
#
# ⚠️ 两个关键前提:
#  1) 这个 bucket 必须【提前创建好】(见 README 的 bootstrap 步骤)。
#     因为 `terraform init` 就要连它 —— 先有桶,才能 init。这叫"先有鸡还是先有蛋":
#     存 state 的桶,本身不能用这套 Terraform 来建(它还没 init 呢)。
#  2) backend 配置块【不能用变量 var.xxx】,只能写死字符串。
#     所以下面 bucket 要改成你自己创建的、全局唯一的桶名(GCS 桶名全球唯一)。
terraform {
  backend "gcs" {
    bucket = "REPLACE-with-your-unique-state-bucket" # ← 改成你创建的桶名
    prefix = "day04"                                 # 桶内的"子目录",用来区分不同 config/环境
  }
}
