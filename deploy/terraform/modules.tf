module "cloudflare_zero_trust" {
  source                = "./cloudflare_zero_trust"
  cloudflare_token      = data.onepassword_item.cloudflare.credential
  cloudflare_account_id = data.onepassword_item.cloudflare_account_id.credential
}
