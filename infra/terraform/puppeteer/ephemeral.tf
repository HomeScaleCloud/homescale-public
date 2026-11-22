locals {
  ephemeral_enabled_modules = {
    for key, module in local.terrakube_modules :
    key => module
    if try(module.executor.ephemeral.enabled, false)
  }

  ephemeral_resource_defaults = {
    for key, module in local.ephemeral_enabled_modules :
    key => {
      TERRAKUBE_ENABLE_EPHEMERAL_EXECUTOR = "1"
      EPHEMERAL_CONFIG_ENVFROM_CONFIG_MAP = "terrakube-executor-config"
      EPHEMERAL_CPU_REQUEST               = try(module.executor.ephemeral.resources.cpuRequest, "250m")
      EPHEMERAL_CPU_LIMIT                 = try(module.executor.ephemeral.resources.cpuLimit, "1")
      EPHEMERAL_MEMORY_REQUEST            = try(module.executor.ephemeral.resources.memoryRequest, "512Mi")
      EPHEMERAL_MEMORY_LIMIT              = try(module.executor.ephemeral.resources.memoryLimit, "1Gi")
    }
  }

  ephemeral_variables = {
    for pair in flatten([
      for workspace, vars in local.ephemeral_resource_defaults : [
        for key, value in vars : { workspace = workspace, key = key, value = value }
      ]
    ]) : "${pair.workspace}-${pair.key}" => pair
  }
}

resource "terrakube_workspace_variable" "ephemeral" {
  for_each = local.ephemeral_variables

  organization_id = data.terrakube_organization.homescale.id
  workspace_id    = terrakube_workspace_vcs.module[each.value.workspace].id
  key             = each.value.key
  value           = each.value.value
  category        = "ENV"
  description     = "Ephemeral executor configuration (${each.value.key})"
  sensitive       = false
  hcl             = false
}

resource "terrakube_workspace_variable" "ephemeral_service_account" {
  organization_id = data.terrakube_organization.homescale.id
  workspace_id    = terrakube_workspace_vcs.module["puppeteer"].id
  key             = "EPHEMERAL_CONFIG_SERVICE_ACCOUNT"
  value           = "terrakube-executor-puppeteer"
  category        = "ENV"
  description     = "Dedicated, isolated Kubernetes ServiceAccount for puppeteer's ephemeral job pods only"
  sensitive       = false
  hcl             = false
}
