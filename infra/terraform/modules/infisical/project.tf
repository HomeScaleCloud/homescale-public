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

resource "infisical_project_environment" "development" {
  project_id = infisical_project.homescale.id
  name       = "development"
  slug       = "development"
}
