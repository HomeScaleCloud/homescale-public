resource "netbird_policy" "region_router_ssh" {
  name    = "Region Router SSH"
  enabled = true
  rule {
    action        = "accept"
    bidirectional = false
    enabled       = true
    protocol      = "netbird-ssh"
    name          = "Region Router SSH"
    sources       = [netbird_group.github_actions.id, data.netbird_group.sg_ssh_admin.id]
    destinations  = [netbird_group.region_routers.id]
    authorized_groups = {
      (data.netbird_group.sg_ssh_admin.id) = ["admin"]
      (netbird_group.github_actions.id)    = ["admin"]
    }
  }
}
