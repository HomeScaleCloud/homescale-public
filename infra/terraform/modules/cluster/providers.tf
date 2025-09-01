terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
    }
    onepassword = {
      source  = "1Password/onepassword"
    }
    tailscale = {
      source  = "tailscale/tailscale"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}

provider "tailscale" {
  tailnet             = "homescale.cloud"
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
}