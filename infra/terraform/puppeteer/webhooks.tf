resource "terrakube_workspace_webhook_v2" "module" {
  for_each = local.terrakube_modules

  organization_id = data.terrakube_organization.homescale.id
  workspace_id    = terrakube_workspace_vcs.module[each.key].id
  migrated_v2     = true
}

resource "terrakube_workspace_webhook_event" "push" {
  for_each = local.terrakube_modules

  webhook_id  = terrakube_workspace_webhook_v2.module[each.key].id
  template_id = data.terrakube_organization_template.plan_and_apply.id
  event       = "PUSH"
  branch      = ["main"]
  path        = [".*"]
  path_type   = "REGEX"
}

resource "terrakube_workspace_webhook_event" "pull_request" {
  for_each = local.terrakube_modules

  webhook_id          = terrakube_workspace_webhook_v2.module[each.key].id
  template_id         = data.terrakube_organization_template.default.id
  event               = "PULL_REQUEST"
  pr_workflow_enabled = true
  pr_apply_enabled    = false
}
