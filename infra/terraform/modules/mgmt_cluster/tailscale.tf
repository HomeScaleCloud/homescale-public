resource "tailscale_oauth_client" "k8s" {
  description = "k8s"
  scopes      = ["devices:core", "auth_keys", "services"]
  tags        = ["tag:k8s"]
}

resource "tailscale_tailnet_key" "node_prod" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 7776000
  description   = "node-key-prod"
  tags          = ["tag:node", "tag:env-prod"]
}

resource "tailscale_tailnet_key" "node_test" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 7776000
  description   = "node-key-test"
  tags          = ["tag:node", "tag:env-test"]
}

resource "tailscale_tailnet_key" "node_lab" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 7776000
  description   = "node-key-lab"
  tags          = ["tag:node", "tag:env-lab"]
}
