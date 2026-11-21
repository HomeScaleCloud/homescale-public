terraform {
  required_providers {
    infisical = {
      source  = "infisical/infisical"
      version = "0.20.15"
    }
    terrakube = {
      source  = "terrakube-io/terrakube"
      version = "0.34.0"
    }
    github = {
      source  = "integrations/github"
      version = "6.13.0"
    }
  }
}

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

provider "terrakube" {
  endpoint = "https://REDACTED"
  token    = try(file("/var/run/secrets/terrakube/token"), null)
}

provider "github" {
  owner = "HomeScaleCloud"
  app_auth {
    id              = data.infisical_secrets.ci.secrets["GITHUB_APP_ID"].value
    installation_id = data.infisical_secrets.ci.secrets["GITHUB_APP_INSTALLATION_ID"].value
    pem_file        = data.infisical_secrets.ci.secrets["GITHUB_APP_PRIVATE_KEY"].value
  }
}
