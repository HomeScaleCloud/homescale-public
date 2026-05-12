resource "netbird_account_settings" "settings" {
  peer_login_expiration              = 345600
  peer_login_expiration_enabled      = true
  peer_inactivity_expiration_enabled = false
  regular_users_view_blocked         = true
  groups_propagation_enabled         = true
  dns_domain                         = "REDACTED"
  auto_update_version                = "latest"
  peer_expose_enabled                = true
  peer_expose_groups                 = [data.netbird_group.all.id]
  user_approval_required             = false
}

data "netbird_reverse_proxy_clusters" "all" {}

resource "netbird_reverse_proxy_domain" "ext" {
  domain         = "REDACTED"
  target_cluster = data.netbird_reverse_proxy_clusters.all.clusters[0].address
}
