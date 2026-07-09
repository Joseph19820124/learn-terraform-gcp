# registry/main.tf —— 镜像仓库(GCP 版 ECR)。跟前几天 AWS 的 ecr/ 一样，
# 单独一个 stack，先 apply 出来、build+push 完镜像再去 apply app/。

terraform {
  required_version = ">= 1.10"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.39"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_artifact_registry_repository" "this" {
  location      = var.region
  repository_id = var.name
  format        = "DOCKER"
  description   = "day12 caller/callee images"
}
