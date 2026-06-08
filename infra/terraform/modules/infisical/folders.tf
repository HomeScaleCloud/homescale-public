resource "infisical_secret_folder" "github_actions" {
  project_id       = data.infisical_projects.homescale.id
  environment_slug = var.environment
  folder_path      = "/"
  name             = "github-actions"
}

resource "infisical_secret_folder" "k8s" {
  project_id       = data.infisical_projects.homescale.id
  environment_slug = var.environment
  folder_path      = "/"
  name             = "k8s"
}

resource "infisical_secret_folder" "k8s_argocd" {
  project_id       = data.infisical_projects.homescale.id
  environment_slug = var.environment
  folder_path      = "/k8s"
  name             = "argocd"
  depends_on       = [infisical_secret_folder.k8s]
}

resource "infisical_secret_folder" "k8s_cloudflare" {
  project_id       = data.infisical_projects.homescale.id
  environment_slug = var.environment
  folder_path      = "/k8s"
  name             = "cloudflare"
  depends_on       = [infisical_secret_folder.k8s]
}

resource "infisical_secret_folder" "k8s_netbird" {
  project_id       = data.infisical_projects.homescale.id
  environment_slug = var.environment
  folder_path      = "/k8s"
  name             = "netbird"
  depends_on       = [infisical_secret_folder.k8s]
}

resource "infisical_secret_folder" "k8s_omni" {
  project_id       = data.infisical_projects.homescale.id
  environment_slug = var.environment
  folder_path      = "/k8s"
  name             = "omni"
  depends_on       = [infisical_secret_folder.k8s]
}
