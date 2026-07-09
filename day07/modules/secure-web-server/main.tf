# modules/secure-web-server/main.tf —— 把 day06 学到的"安全基线"封装成模块：
#   - 镜像用 image family 动态解析(不写死)
#   - SSH 默认不开放，HTTP 按预期开放
#   - 锁定 provider 版本(在根配置里做，模块本身不重复写)
#   - 有 outputs
#
# 封装的价值：day06 那些"要注意的点"以后不用每次新建机器都重新想一遍——
# 用这个模块，安全基线自动就是对的。以后想改基线(比如加个监控 agent、
# 换成 Ubuntu)，只改这一份模块代码，所有调用它的地方全部同步生效。

data "google_compute_image" "this" {
  family  = var.image_family
  project = var.image_project
}

resource "google_compute_firewall" "allow_http" {
  name    = "${var.name}-allow-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"] # web 服务器的预期暴露
  target_tags   = [var.name]
}

resource "google_compute_firewall" "allow_ssh" {
  # 和 day06 一样：默认不创建，只有调用方显式传 ssh_source_ranges 才开。
  count   = length(var.ssh_source_ranges) > 0 ? 1 : 0
  name    = "${var.name}-allow-ssh"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = [var.name]
}

resource "google_compute_instance" "this" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = [var.name]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.this.self_link
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  # var.message 是模块对外暴露的"内容"旋钮——调用方只需要传一句话，
  # 不用知道 nginx 怎么装、首页怎么写。这是好的模块接口设计：
  # 暴露"要什么"，隐藏"怎么做"。
  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update -y
    apt-get install -y nginx
    echo "<h1>${var.message}</h1>" > /var/www/html/index.html
    systemctl enable nginx
    systemctl start nginx
  EOT
}
