module "cluster" {
  source                        = "./modules/cluster"
  cluster                       = "atlas"
  nodes                         = ["talos-kva-re7"]
  vip                           = "10.1.245.15"
  tailscale_oauth_client_id     = data.onepassword_item.tailscale.username
  tailscale_oauth_client_secret = data.onepassword_item.tailscale.password
  op_service_account_token      = var.op_service_account_token
}