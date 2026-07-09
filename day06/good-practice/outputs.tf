# 反模式 #3 修正:AWS 版没有 outputs.tf，apply 完你得自己去控制台/CLI 查 IP。
# 这里 apply 完直接打印出访问地址，不用再去别的地方查。

output "instance_name" {
  value = google_compute_instance.web.name
}

output "public_ip" {
  description = "VM 的公网 IP"
  value       = google_compute_instance.web.network_interface[0].access_config[0].nat_ip
}

output "web_url" {
  description = "打开这个 URL 应该能看到 Welcome 页面"
  value       = "http://${google_compute_instance.web.network_interface[0].access_config[0].nat_ip}/"
}

output "image_used" {
  description = "本次 apply 实际用到的镜像(证明不是写死的，而是当前解析出的最新版本)"
  value       = data.google_compute_image.web.self_link
}
