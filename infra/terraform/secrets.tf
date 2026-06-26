data "infisical_secrets" "github_actions" {
  env_slug     = "prod"
  folder_path  = "/github-actions"
  workspace_id = module.infisical.project_id
}
