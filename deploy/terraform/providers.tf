terraform {
  required_providers {
    onepassword = {
      source  = "1Password/onepassword"
      version = "2.1.2"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.1.0"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.51.0"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.19.0"
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
  tailnet             = "homescale.cloud"
  oauth_client_id     = data.onepassword_item.tailscale.password
  oauth_client_secret = data.onepassword_item.tailscale.credential
}
