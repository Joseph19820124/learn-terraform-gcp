# backend.tf —— 沿用 day04 的 GCS 远程 state 思路，这次换成 AWS S3，并且是
# "partial configuration":bucket/key/region 全部留空，故意不写死。
#
# 原因:day04 只有一个环境，桶名和 prefix 写死在这个文件里就行。这一天要跑
# dev/staging/prod 三个环境，如果 key 也写死，三个环境会共用同一份 state ——
# 一次 dev 的 apply 就可能把 prod 的资源改掉或删掉，这是多环境最容易踩的坑。
#
# 所以这里只声明"用 S3 backend"，具体连哪个桶、哪个 key，由 `terraform init`
# 时的 `-backend-config=<file>` 参数在初始化那一刻决定 —— 三个环境对应
# backend-configs/ 下三个不同的 .hcl 文件，key 各不相同(day20/dev/…、
# day20/staging/…、day20/prod/…)，物理上就是三份完全独立的 state。
#
# use_lockfile = true 是 Terraform 1.10+ 原生支持的 S3 state locking(用 S3
# 的条件写入实现锁，不需要像老教程那样再建一张 DynamoDB 锁表)——这一点上
# AWS 终于追上了 day04 里讲过的 GCS(GCS 从一开始就不需要额外的锁表)。
terraform {
  backend "s3" {
    use_lockfile = true
  }
}
