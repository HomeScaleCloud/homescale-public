resource "netbird_policy" "region_mgmt" {
  name    = "Region Mgmt Networks"
  enabled = true
  rule {
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = ["80", "443", "8443", "6443", "22"]
    name          = "Region Mgmt Networks"
    sources       = [netbird_group.github_actions.id, data.netbird_group.sg_k8s_admin.id]
    destinations  = [data.netbird_group.net_region_mgmt.id]
  }
}

resource "netbird_policy" "region_bmc" {
  name    = "Region BMC Networks"
  enabled = true
  rule {
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = ["80", "443", "8443", "22"]
    name          = "Region BMC Networks"
    sources       = [netbird_group.github_actions.id, data.netbird_group.sg_k8s_admin.id]
    destinations  = [data.netbird_group.net_region_bmc.id]
  }
}

resource "netbird_policy" "omni_k8s" {
  name    = "Omni (k8s proxy)"
  enabled = true
  rule {
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = ["443"]
    name          = "Omni (k8s proxy)"
    sources       = [netbird_group.github_actions.id, data.netbird_group.sg_k8s_admin.id]
    destinations  = [netbird_group.omni_k8s.id]
  }
}

resource "netbird_policy" "k8s" {
  name    = "Kubernetes"
  enabled = true
  rule {
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = ["443"]
    name          = "Kubernetes"
    sources       = [data.netbird_group.team_infra_plat.id, data.netbird_group.team_sec_plat.id, data.netbird_group.sg_k8s_admin.id]
    destinations  = [netbird_group.k8s.id]
  }
}

locals {
  app_yaml_files = fileset("${path.module}/../../../../apps", "*/app.yaml")

  app_yamls = {
    for f in local.app_yaml_files :
    split("/", f)[0] => yamldecode(file("${path.module}/../../../../apps/${f}"))
  }

  app_policies = {
    for name, y in local.app_yamls :
    name => y.netbird.policy
    if try(y.netbird.policy, null) != null
  }

  # One entry per rule: single-rule apps use app_name, multi-rule apps use app_name-N
  app_policy_rules = merge([
    for app_name, policy in local.app_policies : {
      for idx, rule in policy.rules :
      length(policy.rules) == 1 ? app_name : "${app_name}-${idx}" => merge(rule, { app = app_name })
    }
  ]...)

  netbird_source_groups = merge(
    {
      "all"             = data.netbird_group.all.id
      "team-infra-plat" = data.netbird_group.team_infra_plat.id
      "team-sec-plat"   = data.netbird_group.team_sec_plat.id
      "github-actions"  = netbird_group.github_actions.id
      "owners"          = data.netbird_group.owners.id
      "sg-k8s-admin"    = data.netbird_group.sg_k8s_admin.id
    },
    { for k in local.app_names : "app:${k}" => netbird_group.app[k].id }
  )
}

resource "netbird_policy" "app" {
  for_each = local.app_policy_rules

  name    = "app-${each.key}"
  enabled = true

  rule {
    action        = "accept"
    bidirectional = false
    enabled       = true
    name          = "app-${each.key}"
    protocol      = each.value.protocol
    ports         = try(each.value.ports, [])
    sources       = [for s in each.value.sources : local.netbird_source_groups[s]]
    destinations  = [netbird_group.app[each.value.app].id]
  }
}
