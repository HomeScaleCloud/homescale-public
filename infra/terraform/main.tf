module "cluster_atlas" {
  source                        = "./modules/cluster"
  cluster                       = "atlas"
  region                        = "boa1"
  platform                      = "metal"
  tailscale_tailnet             = "tempel-carp.ts.net"
  tailscale_oauth_client_id     = data.onepassword_item.tailscale.username
  tailscale_oauth_client_secret = data.onepassword_item.tailscale.password
  op_service_account_token      = var.op_service_account_token
}
