module "harvester" {
  source = "./harvester"
  region = "BOA1"
  op_service_account_token = var.op_service_account_token
  mgmt_cidr = var.mgmt_cidr
}