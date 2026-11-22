resource "terrakube_workspace_schedule" "module" {
  for_each = local.terrakube_modules

  workspace_id = terrakube_workspace_vcs.module[each.key].id
  template_id  = data.terrakube_organization_template.plan_and_apply.id
  schedule     = try(each.value.schedule, "0 0 * * * ?")
}
