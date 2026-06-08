resource "infisical_secret_folder" "k8s_argocd" {
  project_id       = data.infisical_projects.homescale.id
  environment_slug = var.environment
  folder_path      = "/k8s"
  name             = "argocd"
}

resource "infisical_secret_folder" "k8s_cloudflare" {
  project_id       = data.infisical_projects.homescale.id
  environment_slug = var.environment
  folder_path      = "/k8s"
  name             = "cloudflare"
}

resource "infisical_secret_folder" "k8s_netbird" {
  project_id       = data.infisical_projects.homescale.id
  environment_slug = var.environment
  folder_path      = "/k8s"
  name             = "netbird"
}

resource "infisical_secret_folder" "k8s_omni" {
  project_id       = data.infisical_projects.homescale.id
  environment_slug = var.environment
  folder_path      = "/k8s"
  name             = "omni"
}
