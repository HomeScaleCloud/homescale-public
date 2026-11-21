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
