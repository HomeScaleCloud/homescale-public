terraform {
  required_providers {
    infisical = {
      source  = "infisical/infisical"
      version = "0.20.23"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}

// Both methods authenticate as the same "ci" identity (var.infisical_github_actions,
// full project-admin, provisioned outside Terraform — see variables.tf), just via a
// different credential: "oidc" (default) is CI's GitHub-OIDC token, used for every
// push/PR run on a GitHub-hosted runner. "universal" is for a human running `hsctl run
// terraform -e local` from their own machine — no GitHub OIDC token is available outside
// an Actions runner, so that path uses this same identity's universal auth client
// ID/secret instead (stored directly in Infisical's /ci, fetched via the operator's own
// already-authenticated `infisical` CLI session — see hsctl.d/run.sh's
// _run_script_local_secrets). This is the only way to bootstrap infra from scratch,
// before CI can reach anything.
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
