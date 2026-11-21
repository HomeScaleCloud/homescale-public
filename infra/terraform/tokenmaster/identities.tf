resource "infisical_identity" "k8s_operator" {
  name   = "k8s-operator"
  org_id = var.org_id
  role   = "no-access"
}

resource "infisical_identity_universal_auth" "k8s_operator" {
  identity_id          = infisical_identity.k8s_operator.id
  access_token_ttl     = 3600
  access_token_max_ttl = 86400
  access_token_trusted_ips = [
    { ip_address = "0.0.0.0/0" },
    { ip_address = "::/0" },
  ]
}

resource "infisical_identity_universal_auth_client_secret" "k8s_operator" {
  identity_id = infisical_identity.k8s_operator.id
}

resource "infisical_project_identity" "k8s_operator" {
  project_id  = data.infisical_projects.homescale.id
  identity_id = infisical_identity.k8s_operator.id
  roles = [{
    role_slug    = "viewer"
    is_temporary = false
  }]
}

resource "infisical_secret" "k8s_operator_client_id" {
  name         = "INFISICAL_OPERATOR_CLIENT_ID"
  value        = infisical_identity_universal_auth_client_secret.k8s_operator.client_id
  env_slug     = var.environment
  workspace_id = data.infisical_projects.homescale.id
  folder_path  = "/k8s/infisical"
}

resource "infisical_secret" "k8s_operator_client_secret" {
  name         = "INFISICAL_OPERATOR_CLIENT_SECRET"
  value        = infisical_identity_universal_auth_client_secret.k8s_operator.client_secret
  env_slug     = var.environment
  workspace_id = data.infisical_projects.homescale.id
  folder_path  = "/k8s/infisical"
}

// infisical_org_id has no default and isn't itself an Infisical-stored value today (CI
// gets it from a plain GitHub Actions repo secret, which is how anything reaches Infisical
// in the first place) — seeded here, by this same apply, from the value CI is already
// supplying, into the same /ci folder everything else a human needs for a local
// `hsctl run terraform -e local` bootstrap already lives in (TAILSCALE_*,
// INFISICAL_CI_CLIENT_ID/_SECRET, CLOUDFLARE_API_TOKEN, TF_TOKEN_app_terraform_io).
resource "infisical_secret" "ci_infisical_org_id" {
  name         = "INFISICAL_ORG_ID"
  value        = var.org_id
  env_slug     = var.environment
  workspace_id = data.infisical_projects.homescale.id
  folder_path  = "/ci"
}
