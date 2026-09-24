// Names must be exactly client_id/client_secret -- the tailscale-operator
// chart reads them verbatim from its "operator-oauth" Secret.
resource "infisical_secret" "tailscale_k8s_operator_client_id" {
  name         = "client_id"
  value        = tailscale_oauth_client.k8s_operator.id
  env_slug     = "prod"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/k8s/tailscale"
}

resource "infisical_secret" "tailscale_k8s_operator_client_secret" {
  name         = "client_secret"
  value        = tailscale_oauth_client.k8s_operator.key
  env_slug     = "prod"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/k8s/tailscale"
}

resource "infisical_secret" "tailscale_automatron_client_id" {
  name         = "TAILSCALE_CLIENT_ID"
  value        = tailscale_oauth_client.automatron.id
  env_slug     = "prod"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/k8s/automatron"
}

resource "infisical_secret" "tailscale_automatron_client_secret" {
  name         = "TAILSCALE_CLIENT_SECRET"
  value        = tailscale_oauth_client.automatron.key
  env_slug     = "prod"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/k8s/automatron"
}
