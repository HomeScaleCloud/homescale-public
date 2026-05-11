resource "netbird_token" "k8s_operator" {
  user_id         = netbird_user.k8s_operator.id
  name            = "Kubernetes Operator"
  expiration_days = 30
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
