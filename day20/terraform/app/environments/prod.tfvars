# prod:三个任务起步(避免单点)，规格和 staging 一致 —— 这个 demo 的重点是
# "环境隔离"本身，不是"prod 要多大"，真实项目请按实际负载测试再定规格。
region       = "us-east-1"
name         = "day20"
environment  = "prod"
caller_image = "<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/day20-caller:v1"
callee_image = "<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/day20-callee:v1"

desired_count = 3
cpu           = 512
memory        = 1024
