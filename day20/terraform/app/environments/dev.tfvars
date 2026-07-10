# dev:最小配置，够验证功能就行，不追求高可用。
region       = "us-east-1"
name         = "day20"
environment  = "dev"
caller_image = "<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/day20-caller:v1"
callee_image = "<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/day20-callee:v1"

desired_count = 1
cpu           = 256
memory        = 512
