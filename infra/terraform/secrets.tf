data "onepassword_vault" "github_actions" {
  name = "github-actions"
}

data "onepassword_vault" "k8s" {
  name = "k8s"
}

data "onepassword_item" "cloudflare" {
  vault = "github-actions"
  title = "cloudflare"
}

data "onepassword_item" "cloudflare_account_id" {
  vault = "github-actions"
  title = "cloudflare-account-id"
}

data "onepassword_item" "cloudflare_zone_id" {
  vault = "github-actions"
  title = "cloudflare-zone-id"
}

data "onepassword_item" "digitalocean" {
  vault = "github-actions"
  title = "digitalocean"
}

data "onepassword_item" "netbird" {
  vault = "github-actions"
  title = "netbird"
}

resource "onepassword_item" "netbird" {
  vault    = data.onepassword_vault.k8s.uuid
  title    = "netbird"
  password = netbird_token.k8s_operator.token
}
