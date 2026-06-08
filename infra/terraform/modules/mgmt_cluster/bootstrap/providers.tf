terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.0"
    }
  }
}

provider "kubernetes" {
  host                   = var.k8s_endpoint
  token                  = var.k8s_token
  cluster_ca_certificate = var.k8s_ca
}
