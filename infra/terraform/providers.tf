terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "2.2.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.15.0"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.72.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.25.0"
    }
    rancher2 = {
      source  = "rancher/rancher2"
      version = "8.5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
  }
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}


provider "cloudflare" {
  api_token = data.onepassword_item.cloudflare.credential
}

provider "digitalocean" {
  token = data.onepassword_item.digitalocean.credential
}

provider "tailscale" {
  tailnet             = data.onepassword_item.tailscale_tailnet.credential
  oauth_client_id     = data.onepassword_item.tailscale.username
  oauth_client_secret = data.onepassword_item.tailscale.password
}
