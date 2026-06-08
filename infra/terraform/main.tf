module "infisical" {
  source = "./modules/infisical"
  org_id = var.infisical_org_id
}

module "netbird" {
  source                 = "./modules/netbird"
  netbird_token          = var.netbird_token
  infisical_workspace_id = module.infisical.project_id
}

module "mgmt_cluster" {
  source                               = "./modules/mgmt_cluster"
  digitalocean_token                   = var.digitalocean_token
  k8s_version                          = "1.34."
  region                               = "lon1"
  infisical_workspace_id               = module.infisical.project_id
  infisical_k8s_operator_client_id     = module.infisical.k8s_mgmt_operator_client_id
  infisical_k8s_operator_client_secret = module.infisical.k8s_mgmt_operator_client_secret
  argocd_deploy_key                    = var.argocd_deploy_key
}

# module "region_boa1" {
#   source                 = "./modules/region"
#   region                 = "boa1"
#   infisical_workspace_id = module.infisical.project_id
#   netbird_token          = var.netbird_token
#   mgmt_cidr              = "10.1.245.0/24"
#   bmc_cidr               = "10.1.246.0/24"
# }
