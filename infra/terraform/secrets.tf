data "onepassword_vault" "common" {
  name = "common"
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

data "onepassword_item" "tailscale_tailnet" {
  vault = "common"
  title = "tailscale-tailnet"
}

data "onepassword_item" "tailscale_slack" {
  vault = "github-actions"
  title = "tailscale-slack"
}
