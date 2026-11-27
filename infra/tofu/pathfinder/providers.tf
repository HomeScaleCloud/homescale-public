terraform {
  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.30.0"
    }
    infisical = {
      source  = "infisical/infisical"
      version = "0.20.23"
    }
  }
}

// See tokenmaster/providers.tf for why there are two auth methods.
provider "infisical" {
  auth = var.infisical_auth_method == "universal" ? {
    universal = {
      client_id     = var.infisical_universal_auth_client_id
      client_secret = var.infisical_universal_auth_client_secret
    }
    } : {
    oidc = {
      identity_id = var.infisical_github_actions
    }
  }
}

provider "tailscale" {
  oauth_client_id     = data.infisical_secrets.ci.secrets["TAILSCALE_OAUTH_CLIENT_ID"].value
  oauth_client_secret = data.infisical_secrets.ci.secrets["TAILSCALE_OAUTH_CLIENT_SECRET"].value
  tailnet             = data.infisical_secrets.ci.secrets["TAILSCALE_TAILNET"].value
}
