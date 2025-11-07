module "cluster_atlas" {
  source                        = "./modules/cluster"
  cluster                       = "atlas"
  region                        = "boa1"
  platform                      = "metal"
  gateway                       = "10.1.245.1"
  controlplane_vip              = "10.1.245.15"
  controlplane_nodes            = ["10.1.245.5"]
  workloads_on_controlplane     = true
  talos_version                 = "v1.11.2"
  talos_disk_selector           = { size = 525112713216 }
  app_nfs_provisioner_enabled   = true
  nfs_server                    = "10.1.245.4"
  nfs_path                      = "/mnt/data/apps"
  app_home_assistant_enabled    = true
  tailscale_tailnet             = data.onepassword_item.tailscale_tailnet.username
  tailscale_oauth_client_id     = data.onepassword_item.tailscale.username
  tailscale_oauth_client_secret = data.onepassword_item.tailscale.password
  op_service_account_token      = var.op_service_account_token
}
