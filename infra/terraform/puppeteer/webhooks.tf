resource "terrakube_workspace_webhook_v2" "module" {
  for_each = local.terrakube_modules

  organization_id = data.terrakube_organization.homescale.id
  workspace_id    = terrakube_workspace_vcs.module[each.key].id
  migrated_v2     = true
}

resource "terrakube_workspace_webhook_event" "push" {
  for_each = local.terrakube_modules

  webhook_id = terrakube_workspace_webhook_v2.module[each.key].id
  event      = "PUSH"
  branch     = ["main"]
  path       = ["infra/terraform/${each.key}/**"]
  path_type  = "PATTERN"
}
