data "infisical_secrets" "ci" {
  env_slug     = "prod"
  folder_path  = "/ci"
  workspace_id = module.infisical.project_id
}

data "infisical_secrets" "oidc" {
  env_slug     = "prod"
  folder_path  = "/k8s/oidc"
  workspace_id = module.infisical.project_id
}
