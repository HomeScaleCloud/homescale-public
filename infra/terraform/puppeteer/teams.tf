resource "terrakube_team" "team_infra_plat" {
  organization_id = data.terrakube_organization.homescale.id
  name            = "3a65b126-4dbe-4013-88dd-08fb8f45f6f7"
  role            = "admin"
}

resource "terrakube_team" "ci" {
  organization_id = data.terrakube_organization.homescale.id
  name            = "ci"
  role            = "admin"
}

resource "terrakube_team_token" "ci" {
  team_name   = terrakube_team.ci.name
  description = "puppeteer's own Terrakube provider auth"
  days        = 3650
  hours       = 0
  minutes     = 0
}

resource "infisical_secret" "terrakube_team_token" {
  name         = "TERRAKUBE_TEAM_TOKEN"
  value        = terrakube_team_token.ci.value
  env_slug     = "prod"
  workspace_id = local.infisical_workspace_id
  folder_path  = "/ci"
}
