data "onepassword_vault" "core" {
  name = "core"
}

data "onepassword_vault" "manor" {
  name = "manor"
}

data "onepassword_vault" "github_actions" {
  name = "github-actions"
}

data "onepassword_item" "cloudflare" {
  vault = "common"
  title = "cloudflare"
}

data "onepassword_item" "cloudflare_account_id" {
  vault = "common"
  title = "cloudflare-account-id"
}

data "onepassword_item" "cloudflare_zone_id" {
  vault = "common"
  title = "cloudflare-zone-id"
}

data "onepassword_item" "digitalocean" {
  vault = "common"
  title = "digitalocean"
}

data "onepassword_item" "tailscale" {
  vault = "github-actions"
  title = "tailscale"
}

resource "onepassword_item" "tailscale_oauth_k8s_core" {
  vault    = data.onepassword_vault.core.uuid
  title    = "tailscale"
  username = tailscale_oauth_client.k8s_core.id
  password = tailscale_oauth_client.k8s_core.key
}

resource "onepassword_item" "tailscale_oauth_k8s_manor" {
  vault    = data.onepassword_vault.manor.uuid
  title    = "tailscale"
  username = tailscale_oauth_client.k8s_manor.id
  password = tailscale_oauth_client.k8s_manor.key
}
