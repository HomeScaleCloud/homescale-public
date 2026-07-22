terraform {
  required_providers {
    infisical = {
      source  = "infisical/infisical"
      version = "0.19.5"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.22.0"
    }
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.3.0"
    }
    netbird = {
      source  = "netbirdio/netbird"
      version = "0.0.9"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
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

provider "netbird" {
  token = var.netbird_token
}
