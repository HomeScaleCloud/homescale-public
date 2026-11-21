data "terrakube_organization" "homescale" {
  name = "HomeScale"
}

data "terrakube_vcs" "github" {
  name            = var.vcs_connection_name
  organization_id = data.terrakube_organization.homescale.id
}

data "terrakube_organization_template" "default" {
  name            = var.organization_template_name
  organization_id = data.terrakube_organization.homescale.id
}
