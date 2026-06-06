terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "2.2.1"
    }
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

provider "onepassword" {
  service_account_token = var.op_service_account_token
}
