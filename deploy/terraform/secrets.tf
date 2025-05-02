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
