data "infisical_secrets" "github_actions" {
  env_slug     = "prod"
  folder_path  = "/github-actions"
  workspace_id = module.infisical.project_id
}

data "infisical_secrets" "k8s_argocd_deploy_key" {
  env_slug     = "prod"
  folder_path  = "/k8s/argocd/deploy-key"
  workspace_id = module.infisical.project_id
}
