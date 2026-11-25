terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.29.0"
    }
    infisical = {
      source  = "infisical/infisical"
      version = "0.20.20"
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

provider "cloudflare" {
  api_token = data.infisical_secrets.ci.secrets["CLOUDFLARE_API_TOKEN"].value
}
