module "netbird" {
  source                   = "./modules/netbird"
  netbird_token            = data.onepassword_item.netbird.credential
  op_service_account_token = var.op_service_account_token
}

module "mgmt_cluster" {
  source                   = "./modules/mgmt_cluster"
  digitalocean_token       = data.onepassword_item.digitalocean.credential
  k8s_version              = "1.34."
  region                   = "lon1"
  op_service_account_token = var.op_service_account_token
}

# module "region_boa1" {
#   source                   = "./modules/region"
#   region                   = "boa1"
#   op_service_account_token = var.op_service_account_token
#   netbird_token            = data.onepassword_item.netbird.credential
#   mgmt_cidr                = "10.1.245.0/24"
#   bmc_cidr                 = "10.1.246.0/24"
# }
