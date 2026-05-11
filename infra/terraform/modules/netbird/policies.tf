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
