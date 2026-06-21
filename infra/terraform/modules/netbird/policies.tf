# resource "netbird_policy" "lab" {
#   name    = "Lab Policy"
#   enabled = true
#   rule {
#     action        = "accept"
#     bidirectional = false
#     enabled       = true
#     protocol      = "all"
#     name          = "Lab Policy"
#     sources       = [data.netbird_group.all.id]
#     destinations  = [netbird_group.cluster["lab"].id]
#   }
# }

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

resource "netbird_policy" "argocd" {
  name    = "ArgoCD"
  enabled = true
  rule {
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = ["80", "443"]
    name          = "ArgoCD"
    sources       = [data.netbird_group.team_infra_plat.id]
    destinations  = [netbird_group.app["argocd"].id]
  }
}

resource "netbird_policy" "omni" {
  name    = "Omni"
  enabled = true
  rule {
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = ["80", "443"]
    name          = "Omni"
    sources       = [netbird_group.github_actions.id, netbird_group.app["omni-infra-provider"].id, data.netbird_group.team_infra_plat.id]
    destinations  = [netbird_group.app["omni"].id]
  }
}

resource "netbird_policy" "home_assistant" {
  name    = "Home Assistant"
  enabled = true
  rule {
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = ["80", "443"]
    name          = "Home Assistant"
    sources       = [data.netbird_group.owners.id]
    destinations  = [netbird_group.app["home-assistant"].id]
  }
}

resource "netbird_policy" "metrics" {
  name    = "Metrics"
  enabled = true
  rule {
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = ["80", "443"]
    name          = "Metrics"
    sources       = [data.netbird_group.team_infra_plat.id, data.netbird_group.team_sec_plat.id]
    destinations  = [netbird_group.app["metrics"].id]
  }
}
