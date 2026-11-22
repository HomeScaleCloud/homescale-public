resource "terrakube_organization_tag" "managed_by" {
  organization_id = data.terrakube_organization.homescale.id
  name            = "managed-by"
}

resource "terrakube_workspace_tag" "module" {
  for_each = local.terrakube_modules

  organization_id = data.terrakube_organization.homescale.id
  workspace_id    = terrakube_workspace_vcs.module[each.key].id
  tag_id          = terrakube_organization_tag.managed_by.id
  value           = "puppeteer"
}
