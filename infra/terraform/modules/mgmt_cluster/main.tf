# Enable one module per apply when standing up the mgmt cluster
module "bootstrap_1" {
  source             = "./bootstrap_1"
  region             = "lon1"
  k8s_version        = "1.34."
  digitalocean_token = var.digitalocean_token
}

module "bootstrap_2" {
  depends_on               = [module.bootstrap_1]
  source                   = "./bootstrap_2"
  k8s_endpoint             = module.cluster.k8s_endpoint
  k8s_token                = module.cluster.k8s_token
  k8s_ca                   = module.cluster.k8s_ca
  op_service_account_token = var.op_service_account_token
}

module "bootstrap_3" {
  depends_on               = [module.bootstrap_2]
  source                   = "./bootstrap_3"
  k8s_endpoint             = module.cluster.k8s_endpoint
  k8s_token                = module.cluster.k8s_token
  k8s_ca                   = module.cluster.k8s_ca
  op_service_account_token = var.op_service_account_token
}

module "rancher" {
  depends_on               = [module.bootstrap_3]
  source                   = "./rancher"
  k8s_endpoint             = module.cluster.k8s_endpoint
  k8s_token                = module.cluster.k8s_token
  k8s_ca                   = module.cluster.k8s_ca
  op_service_account_token = var.op_service_account_token
  rancher_token            = module.bootstrap.rancher_token
}
