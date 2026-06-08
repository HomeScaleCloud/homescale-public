resource "infisical_project" "homescale" {
  name                       = "homescale"
  slug                       = "homescale"
  should_create_default_envs = false
}

resource "infisical_project_environment" "production" {
  project_id = infisical_project.homescale.id
  name       = "production"
  slug       = "production"
}

resource "infisical_project_environment" "lab" {
  project_id = infisical_project.homescale.id
  name       = "lab"
  slug       = "lab"
}
