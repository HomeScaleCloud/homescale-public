module "cloudflare" {
  source                 = "./modules/cloudflare"
  infisical_workspace_id = module.infisical.project_id
}

module "infisical" {
  source = "./modules/infisical"
  org_id = var.infisical_org_id
}

module "netbird" {
  source                 = "./modules/netbird"
  infisical_workspace_id = module.infisical.project_id
}

module "mgmt_cluster" {
  source                 = "./modules/mgmt_cluster"
  vultr_api_key          = data.infisical_secrets.github_actions.secrets["VULTR_TOKEN"].value
  k8s_version            = "v1.36.1+2"
  region                 = "lhr"
  infisical_workspace_id = module.infisical.project_id
}

# module "region_boa1" {
#   source                 = "./modules/region"
#   region                 = "boa1"
#   infisical_workspace_id = module.infisical.project_id
#   netbird_token          = var.netbird_token
#   mgmt_cidr              = "10.1.245.0/24"
#   bmc_cidr               = "10.1.246.0/24"
# }
