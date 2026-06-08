resource "infisical_secret_folder" "k8s_netbird" {
  project_id       = data.infisical_projects.homescale.id
  environment_slug = var.environment
  folder_path      = "/k8s"
  name             = "netbird"
}
