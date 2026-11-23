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

data "terrakube_organization_template" "plan_and_apply" {
  name            = "Plan and apply"
  organization_id = data.terrakube_organization.homescale.id
}
