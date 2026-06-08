resource "infisical_secret" "mgmt_kubeconfig" {
  name         = "MGMT_KUBECONFIG"
  value        = digitalocean_kubernetes_cluster.mgmt.kube_config.0.raw_config
  env_slug     = "prod"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/github-actions"
}
