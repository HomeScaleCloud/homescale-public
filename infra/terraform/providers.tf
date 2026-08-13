terraform {
  required_providers {
    infisical = {
      source  = "infisical/infisical"
      version = "0.19.21"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.23.0"
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
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
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

provider "tailscale" {
  oauth_client_id     = data.infisical_secrets.github_actions.secrets["TAILSCALE_OAUTH_CLIENT_ID"].value
  oauth_client_secret = data.infisical_secrets.github_actions.secrets["TAILSCALE_OAUTH_CLIENT_SECRET"].value
  tailnet             = data.infisical_secrets.github_actions.secrets["TAILSCALE_TAILNET"].value
}
