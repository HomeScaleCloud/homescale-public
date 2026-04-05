module "cluster" {
  source             = "./cluster"
  region             = "lon1"
  k8s_version        = "1.34."
  digitalocean_token = var.digitalocean_token
}

# module "bootstrap" {
#   source                   = "./bootstrap"
#   k8s_endpoint             = module.digitalocean_cluster.k8s_endpoint
#   k8s_token                = module.digitalocean_cluster.k8s_token
#   k8s_ca                   = module.digitalocean_cluster.k8s_ca
#   twingate_token           = var.twingate_token
#   op_service_account_token = var.op_service_account_token
# }

# module "rancher" {
#   source = "./rancher"
#   k8s_endpoint = module.digitalocean_cluster.k8s_endpoint
#   k8s_token = module.digitalocean_cluster.k8s_token
#   k8s_ca = module.digitalocean_cluster.k8s_ca
#   op_service_account_token = var.op_service_account_token
#   rancher_token = module.bootstrap.rancher2_bootstrap.mgmt.token
# }
