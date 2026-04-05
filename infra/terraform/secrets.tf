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

data "onepassword_item" "twingate" {
  vault = "github-actions"
  title = "twingate"
}

resource "onepassword_item" "twingate_github_actions_service_key" {
  vault    = data.onepassword_vault.github_actions.uuid
  title    = "twingate-service-key"
  password = twingate_service_account_key.github_actions.token
}
