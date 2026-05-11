resource "netbird_policy" "lab" {
  name    = "Lab Policy"
  enabled = true
  rule {
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "all"
    name          = "Lab Policy"
    sources       = [data.netbird_group.all.id]
    destinations  = [netbird_group.env_lab.id]
  }
}

resource "netbird_policy" "region_mgmt" {
  name    = "Region Mgmt Networks"
  enabled = true
  rule {
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = ["80", "443", "8443", "22"]
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

resource "netbird_policy" "rancher" {
  name    = "Rancher"
  enabled = true
  rule {
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "tcp"
    ports         = ["80", "443"]
    name          = "Rancher"
    sources       = [data.netbird_group.team_infra_plat.id, data.netbird_group.team_sec_plat.id, netbird_group.github_actions.id]
    destinations  = [netbird_group.app_rancher.id]
  }
}
