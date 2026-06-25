data "infisical_secrets" "github_actions" {
  env_slug     = "prod"
  folder_path  = "/github-actions"
  workspace_id = var.infisical_workspace_id
}
