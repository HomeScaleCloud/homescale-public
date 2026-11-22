resource "terrakube_team" "team_infra_plat" {
  organization_id = data.terrakube_organization.homescale.id
  name            = "3a65b126-4dbe-4013-88dd-08fb8f45f6f7"
  role            = "admin"
}

moved {
  from = terrakube_team.ci
  to   = terrakube_team.puppeteer
}

resource "terrakube_team" "puppeteer" {
  organization_id = data.terrakube_organization.homescale.id
  name            = "puppeteer"
  role            = "admin"
}
