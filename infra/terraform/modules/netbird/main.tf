locals {
  public_apps = {
    for name, y in local.app_yamls :
    name => y.netbird.exposePublic
    if try(y.netbird.exposePublic, null) != null
  }
}

module "public_app" {
  for_each = local.public_apps

  source                 = "./public_app"
  name                   = each.key
  cluster                = each.value.cluster
  domain                 = "REDACTED"
  fqdn                   = each.value.fqdn
  peer_groups            = [netbird_group.app[each.key].id, netbird_group.cluster[each.value.cluster].id]
  port                   = tostring(each.value.port)
  protocol               = each.value.protocol
  infisical_workspace_id = var.infisical_workspace_id
}
