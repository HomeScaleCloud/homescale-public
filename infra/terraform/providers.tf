terraform {
  required_providers {
    infisical = {
      source  = "infisical/infisical"
      version = "0.19.36"
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

// Both methods authenticate as the same "ci" identity (var.infisical_github_actions,
// full project-admin, provisioned outside Terraform — see variables.tf; it predates and
// keeps its original GitHub-OIDC auth alongside a universal auth method added for the
// below), just via a different credential: "oidc" (default) is CI's GitHub-OIDC token.
// "universal" is automatron's terraform dispatch — no GitHub OIDC token is available
// inside a Kubernetes Job for it to present, so it uses that same identity's universal
// auth client ID/secret instead (symlinked from Infisical's /ci into /k8s/automatron;
// see terraform.sh). Deliberately not the k8s Infisical Operator's own identity — that
// one stays low-privileged (project member, narrow org identity-reader role) for its
// actual job of syncing secrets, since terraform's own admin-level operations (managing
// identities/org roles) can't be bootstrapped by an identity trying to grant itself
// permission to do so.
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
