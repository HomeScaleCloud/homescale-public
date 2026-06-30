resource "infisical_secret" "mgmt_kubeconfig" {
  name         = "MGMT_KUBECONFIG"
  value        = base64decode(vultr_kubernetes.mgmt.kube_config)
  env_slug     = "prod"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/github-actions"
}
