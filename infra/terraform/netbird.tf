data "netbird_group" "all" {
  name = "All"
}

data "netbird_reverse_proxy_clusters" "all" {}

locals {
  app_names = sort(distinct([
    for app_file in fileset("${path.module}/../../apps", "*/**") : split("/", app_file)[0]
  ]))
}

resource "netbird_account_settings" "settings" {
  peer_login_expiration              = 86400
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

resource "netbird_reverse_proxy_domain" "ext" {
  domain         = "REDACTED"
  target_cluster = data.netbird_reverse_proxy_clusters.all.clusters[0].address
}

resource "netbird_user" "k8s_operator" {
  is_service_user = true
  name            = "Kubernetes Operator"
  is_blocked      = false
  role            = "admin"
}

resource "netbird_token" "k8s_operator" {
  user_id         = netbird_user.k8s_operator.id
  name            = "Kubernetes Operator"
  expiration_days = 30
}

resource "netbird_group" "github_actions" {
  name = "GitHub Actions"
}

resource "netbird_group" "app" {
  for_each = toset(local.app_names)

  name = "app-${each.key}"
}

resource "netbird_setup_key" "github_actions" {
  name                   = "GitHub Actions"
  expiry_seconds         = 86400
  type                   = "reusable"
  allow_extra_dns_labels = true
  auto_groups            = [netbird_group.github_actions.id]
  ephemeral              = true
  usage_limit            = 0
}
