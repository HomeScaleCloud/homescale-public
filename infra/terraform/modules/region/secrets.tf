resource "infisical_secret" "netbird_region_setup_key" {
  name         = "NETBIRD_${upper(var.region)}_SETUP_KEY"
  value        = netbird_setup_key.region_router.key
  env_slug     = "production"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/k8s"
}
