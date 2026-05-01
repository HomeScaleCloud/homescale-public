terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    rancher2 = {
      source = "rancher/rancher2"
    }
    onepassword = {
      source = "1Password/onepassword"
    }
  }
}

provider "kubernetes" {
  host                   = var.k8s_endpoint
  token                  = var.k8s_token
  cluster_ca_certificate = var.k8s_ca
}

provider "rancher2" {
  api_url   = "https://REDACTED"
  bootstrap = true
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}
