module "mgmt_cluster" {
  source                   = "./modules/mgmt_cluster"
  digitalocean_token       = data.onepassword_item.digitalocean.credential
  k8s_version              = "1.34."
  region                   = "lon1"
  op_service_account_token = var.op_service_account_token
  twingate_token           = data.onepassword_item.twingate.credential
}

module "region_boa1" {
  source                                     = "./modules/region"
  region                                     = "boa1"
  op_service_account_token                   = var.op_service_account_token
  twingate_token                             = data.onepassword_item.twingate.credential
  twingate_github_actions_service_account_id = twingate_service_account.github_actions.id
}
