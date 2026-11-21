data "terrakube_organization" "homescale" {
  name = "HomeScale"
}

data "terrakube_vcs" "github" {
  name            = "HomeScale GitHub"
  organization_id = data.terrakube_organization.homescale.id
}

data "terrakube_organization_template" "default" {
  name            = "Plan"
  organization_id = data.terrakube_organization.homescale.id
}
