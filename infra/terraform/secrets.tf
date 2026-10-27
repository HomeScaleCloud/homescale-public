data "infisical_secrets" "ci" {
  env_slug     = "prod"
  folder_path  = "/ci"
  workspace_id = module.infisical.project_id
}
