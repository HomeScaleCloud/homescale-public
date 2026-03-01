module "mgmt_cluster" {
  source                        = "./modules/mgmt_cluster"
  digitalocean_token            = data.onepassword_item.digitalocean.credential
  k8s_version                   = "1.34.1-do.4"
  region                        = "lon1"
  op_service_account_token      = var.op_service_account_token
  tailscale_tailnet             = data.onepassword_item.tailscale_tailnet.credential
  tailscale_oauth_client_id     = data.onepassword_item.tailscale.username
  tailscale_oauth_client_secret = data.onepassword_item.tailscale.password
}
