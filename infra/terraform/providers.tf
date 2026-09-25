terraform {
  required_providers {
    infisical = {
      source  = "infisical/infisical"
      version = "0.19.35"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.25.0"
    }
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.4.1"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}

// "oidc" (default) is CI's GitHub-OIDC-federated identity (var.infisical_github_actions,
// full project-admin, provisioned outside Terraform — see variables.tf). "universal" is
// automatron's terraform dispatch, reusing the k8s Infisical Operator's own identity
// (module.infisical's k8s_operator, "member" role) via its existing client ID/secret —
// there's no GitHub OIDC token available inside a Kubernetes Job for it to present.
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

provider "cloudflare" {}

provider "tailscale" {
  oauth_client_id     = data.infisical_secrets.ci.secrets["TAILSCALE_OAUTH_CLIENT_ID"].value
  oauth_client_secret = data.infisical_secrets.ci.secrets["TAILSCALE_OAUTH_CLIENT_SECRET"].value
  tailnet             = data.infisical_secrets.ci.secrets["TAILSCALE_TAILNET"].value
}
