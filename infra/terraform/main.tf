module "cluster_atlas" {
  source                        = "./modules/cluster"
  cluster                       = "atlas"
  region                        = "boa1"
  controlplane_nodes            = ["10.1.245.5"]
  vip                           = "10.1.245.15"
  talos_version                 = "1.11.2"
  tailscale_oauth_client_id     = data.onepassword_item.tailscale.username
  tailscale_oauth_client_secret = data.onepassword_item.tailscale.password
  op_service_account_token      = var.op_service_account_token
}