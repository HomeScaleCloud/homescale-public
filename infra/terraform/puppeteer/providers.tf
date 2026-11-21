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

// Team token (not the CI identity's own credential) — Terrakube's self-management API
// surface expects a workspace-scoped team token, generated once in the Terrakube UI and
// stored in Infisical's /ci folder alongside the other CI credentials this org already
// keeps there.
provider "terrakube" {
  endpoint = "https://REDACTED/api/v1"
  token    = data.infisical_secrets.ci.secrets["TERRAKUBE_TEAM_TOKEN"].value
}
