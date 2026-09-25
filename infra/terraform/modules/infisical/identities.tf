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
    # "member" (read/write secrets+folders project-wide, no project-admin actions like
    # managing other identities' roles) rather than "viewer" — this identity is now also
    # reused for automatron's terraform dispatch (see providers.tf), which needs to create/
    # update Infisical secrets (volsync, cloudflared tunnel credentials), not just read them.
    role_slug    = "member"
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

// Automatron reuses this same k8s_operator identity for its own Infisical login
// (see INFISICAL_OPERATOR_CLIENT_ID/SECRET above) rather than getting a dedicated
// identity of its own — Infisical machine identities are billed per-identity. This now
// also covers automatron's terraform dispatch (universal auth in providers.tf) — same
// identity, same reasoning, which is why its role above is "member" rather than "viewer".

resource "infisical_secret" "automatron_project_id" {
  name         = "INFISICAL_PROJECT_ID"
  value        = data.infisical_projects.homescale.id
  env_slug     = var.environment
  workspace_id = data.infisical_projects.homescale.id
  folder_path  = "/k8s/automatron"
}

// The Cloudflare Terraform provider auto-detects CLOUDFLARE_API_TOKEN from the process
// environment (no explicit provider argument for it) — CI gets it for free via the bulk
// /ci-folder env export, but automatron's terraform dispatch needs it delivered directly.
// A reference (not a separately-minted token), same pattern as GIT_DEPLOY_KEY elsewhere.
resource "infisical_secret" "automatron_cloudflare_api_token" {
  name         = "CLOUDFLARE_API_TOKEN"
  value        = "$${prod.ci.CLOUDFLARE_API_TOKEN}"
  env_slug     = var.environment
  workspace_id = data.infisical_projects.homescale.id
  folder_path  = "/k8s/automatron"
}

// Same idea: Terraform Cloud auth is also picked up from the process environment
// (TF_TOKEN_<hostname>, dots as underscores — https://developer.hashicorp.com/terraform/cli/config/config-file#credentials),
// which CI already gets for free from the same /ci-folder export.
resource "infisical_secret" "automatron_tfc_token" {
  name         = "TF_TOKEN_app_terraform_io"
  value        = "$${prod.ci.TF_TOKEN_app_terraform_io}"
  env_slug     = var.environment
  workspace_id = data.infisical_projects.homescale.id
  folder_path  = "/k8s/automatron"
}

// infisical_org_id has no default and isn't itself an Infisical-stored value today (CI
// gets it from a plain GitHub Actions repo secret, which is how anything reaches Infisical
// in the first place) — seeded here, by this same apply, from the value CI is already
// supplying, so automatron's own runs can read it back afterwards.
resource "infisical_secret" "automatron_infisical_org_id" {
  name         = "INFISICAL_ORG_ID"
  value        = var.org_id
  env_slug     = var.environment
  workspace_id = data.infisical_projects.homescale.id
  folder_path  = "/k8s/automatron"
}
