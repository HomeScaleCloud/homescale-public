resource "tailscale_oauth_client" "k8s_operator" {
  description = "k8s-${var.cluster}"
  scopes      = ["devices:core", "auth_keys", "services"]
  tags        = ["tag:k8s", "tag:app", "tag:app-argocd", "tag:app-ha", "tag:app-metrics", "tag:env-${var.env}"]
}

resource "tailscale_tailnet_key" "node" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 2592000
  description   = "Node Key"
  tags          = ["tag:node", "tag:env-${var.env}"]
}
