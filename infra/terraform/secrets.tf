resource "random_password" "time_machine_username" {
  length  = 12
  special = false
}

resource "random_password" "time_machine_password" {
  length  = 32
  special = false
}

resource "infisical_secret_folder" "k8s_time_machine" {
  name             = "time-machine"
  environment_slug = "prod"
  project_id       = module.infisical.project_id
  folder_path      = "/k8s"
}

resource "infisical_secret" "time_machine_username" {
  name         = "TM_USERNAME"
  value        = random_password.time_machine_username.result
  env_slug     = "prod"
  workspace_id = module.infisical.project_id
  folder_path  = "/k8s/time-machine"

  depends_on = [infisical_secret_folder.k8s_time_machine]
}

resource "infisical_secret" "time_machine_password" {
  name         = "TM_PASSWORD"
  value        = random_password.time_machine_password.result
  env_slug     = "prod"
  workspace_id = module.infisical.project_id
  folder_path  = "/k8s/time-machine"

  depends_on = [infisical_secret_folder.k8s_time_machine]
}

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
