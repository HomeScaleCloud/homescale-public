module "harvester" {
  source                   = "./harvester"
  region                   = "boa1"
  op_service_account_token = var.op_service_account_token
  mgmt_cidr                = var.mgmt_cidr
  netbird_setup_key        = netbird_setup_key.metal.key
}
