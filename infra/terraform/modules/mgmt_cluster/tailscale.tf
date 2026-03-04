resource "tailscale_oauth_client" "k8s_mgmt" {
  description = "k8s-mgmt"
  scopes      = ["devices:core", "auth_keys", "services"]
  tags        = ["tag:k8s", "tag:k8s-mgmt", "tag:env-mgmt"]
}

resource "tailscale_oauth_client" "k8s_prod" {
  description = "k8s-prod"
  scopes      = ["devices:core", "auth_keys", "services"]
  tags        = ["tag:k8s", "tag:k8s-prod", "tag:env-prod"]
}

resource "tailscale_oauth_client" "test" {
  description = "k8s-test"
  scopes      = ["devices:core", "auth_keys", "services"]
  tags        = ["tag:k8s", "tag:k8s-test", "tag:env-test"]
}

resource "tailscale_oauth_client" "k8s_lab" {
  description = "k8s-lab"
  scopes      = ["devices:core", "auth_keys", "services"]
  tags        = ["tag:k8s", "tag:k8s-lab", "tag:env-lab"]
}

resource "tailscale_tailnet_key" "node_mgmt" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 7776000
  description   = "node-key-mgmt"
  tags          = ["tag:node", "tag:node-mgmt", "tag:env-mgmt"]
}

resource "tailscale_tailnet_key" "node_prod" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 7776000
  description   = "node-key-prod"
  tags          = ["tag:node", "tag:node-prod", "tag:env-prod"]
}

resource "tailscale_tailnet_key" "node_test" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 7776000
  description   = "node-key-test"
  tags          = ["tag:node", "tag:node-test", "tag:env-test"]
}

resource "tailscale_tailnet_key" "node_lab" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = 7776000
  description   = "node-key-lab"
  tags          = ["tag:node", "tag:node-lab", "tag:env-lab"]
}
