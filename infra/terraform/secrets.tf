data "infisical_secrets" "github_actions" {
  env_slug     = "prod"
  folder_path  = "/github-actions"
  workspace_id = module.infisical.project_id
}

data "infisical_secrets" "oidc" {
  env_slug     = "prod"
  folder_path  = "/k8s/oidc"
  workspace_id = module.infisical.project_id
}
