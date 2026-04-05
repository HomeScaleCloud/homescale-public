terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    onepassword = {
      source = "1Password/onepassword"
    }
    rancher2 = {
      source = "rancher/rancher2"
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

provider "rancher2" {
  api_url   = "https://mgmt.homescale.cloud"
  token_key = var.rancher_token
}
