locals {
  terrakube_yaml_files = fileset("${path.module}/..", "*/terrakube.yaml")

  terrakube_modules = {
    for f in local.terrakube_yaml_files :
    split("/", f)[0] => yamldecode(file("${path.module}/../${f}"))
  }
}

resource "terrakube_workspace_vcs" "module" {
  for_each = local.terrakube_modules

  organization_id = data.terrakube_organization.homescale.id
  name            = each.key
  description     = "${each.value.description} - Workspace managed by Puppeteer"

  vcs_id      = data.terrakube_vcs.github.id
  repository  = var.repository
  branch      = var.repository_branch
  folder      = "/infra/terraform/${each.key}"
  template_id = data.terrakube_organization_template.default.id
  iac_type    = "terraform"
  iac_version = each.value.terraformVersion

  execution_mode                      = "remote"
  restrict_apply_to_configured_branch = true
}
