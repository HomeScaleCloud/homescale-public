module "bootstrap" {
  source                   = "./bootstrap"
  k8s_endpoint             = digitalocean_kubernetes_cluster.mgmt.endpoint
  k8s_token                = digitalocean_kubernetes_cluster.mgmt.kube_config.0.token
  k8s_ca                   = base64decode(digitalocean_kubernetes_cluster.mgmt.kube_config.0.cluster_ca_certificate)
  op_service_account_token = var.op_service_account_token
}
