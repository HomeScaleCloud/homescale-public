module "bootstrap" {
  source                               = "./bootstrap"
  k8s_endpoint                         = digitalocean_kubernetes_cluster.mgmt.endpoint
  k8s_token                            = digitalocean_kubernetes_cluster.mgmt.kube_config.0.token
  k8s_ca                               = base64decode(digitalocean_kubernetes_cluster.mgmt.kube_config.0.cluster_ca_certificate)
  infisical_k8s_operator_client_id     = var.infisical_k8s_operator_client_id
  infisical_k8s_operator_client_secret = var.infisical_k8s_operator_client_secret
  argocd_deploy_key                    = var.argocd_deploy_key
}
