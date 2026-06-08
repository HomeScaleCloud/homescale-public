resource "infisical_secret" "netbird_k8s_operator" {
  name         = "NETBIRD_OPERATOR_TOKEN"
  value        = netbird_token.k8s_operator.token
  env_slug     = "production"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/k8s/netbird"
}
