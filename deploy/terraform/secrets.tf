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

resource "onepassword_item" "tailscale_oauth_github_actions" {
  vault    = "icuodmjsrcjgpj3w6zard3nsoa"
  title    = "tailscale"
  username = tailscale_oauth_client.github_actions.id
  password = tailscale_oauth_client.github_actions.key
}

resource "onepassword_item" "tailscale_oauth_operator_core" {
  vault    = "core"
  title    = "tailscale"
  username = tailscale_oauth_client.operator_core.id
  password = tailscale_oauth_client.operator_core.key
}
