terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.3.0"
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

provider "cloudflare" {
  api_token = var.cloudflare_token
}

provider "digitalocean" {
  token             = var.digitalocean_token
  spaces_access_id  = var.digitalocean_spaces_id
  spaces_secret_key = var.digitalocean_spaces_key
}

provider "tailscale" {
  tailnet             = var.tailscale_tailnet
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
}
