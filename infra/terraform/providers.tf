terraform {
  required_providers {
    infisical = {
      source  = "infisical/infisical"
      version = "0.16.28"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.19.1"
    }
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.87.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.3.0"
    }
    netbird = {
      source  = "netbirdio/netbird"
      version = "0.0.9"
    }
  }
}

provider "infisical" {
  auth = {
    oidc = {
      identity_id = var.infisical_github_actions
    }
  }
}

provider "cloudflare" {}

provider "digitalocean" {}

provider "netbird" {
  token = var.netbird_token
}
