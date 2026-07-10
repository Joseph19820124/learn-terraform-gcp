# staging:任务数和规格比 dev 高一档，用来在上线前发现 dev 单实例掩盖不了的问题
# (比如多实例并发、滚动更新)。镜像 tag 通常和 dev 验证过的那个一样(晋升，不重新 build)。
region       = "us-east-1"
name         = "day20"
environment  = "staging"
caller_image = "<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/day20-caller:v1"
callee_image = "<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/day20-callee:v1"

desired_count = 2
cpu           = 512
memory        = 1024
