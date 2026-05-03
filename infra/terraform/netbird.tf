resource "netbird_account_settings" "settings" {
  peer_login_expiration              = 86400
  peer_inactivity_expiration         = 7200
  peer_login_expiration_enabled      = true
  peer_inactivity_expiration_enabled = true
  regular_users_view_blocked         = true
  groups_propagation_enabled         = true
  dns_domain                         = "REDACTED"
  auto_update_version                = "latest"
  peer_expose_enabled                = true
  user_approval_required             = false
}
