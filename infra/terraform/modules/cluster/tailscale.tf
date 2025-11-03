resource "tailscale_oauth_client" "k8s_operator" {
  description = "k8s-${var.cluster}"
  scopes      = ["devices:core", "auth_keys"]
  tags        = ["tag:k8s", "tag:app", "tag:cluster-${var.cluster}", "tag:region-${var.region}"]
}

resource "tailscale_tailnet_key" "node" {
  reusable      = true
  ephemeral     = false
  preauthorized = false
  expiry        = 1200
  description   = "Node Key"
  tags          = ["tag:node", "tag:cluster-${var.cluster}", "tag:region-${var.region}"]
}
