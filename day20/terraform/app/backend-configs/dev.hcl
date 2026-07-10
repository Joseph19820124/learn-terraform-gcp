bucket = "REPLACE-with-your-unique-state-bucket" # ← 改成你创建的桶名，三个环境可以共用同一个桶
key    = "day20/dev/terraform.tfstate"           # ← 只有这一行三个环境不一样，这就是隔离的关键
region = "us-east-1"
