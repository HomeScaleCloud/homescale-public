resource "infisical_secret" "mgmt_vultr_kubeconfig" {
  name         = "MGMT_VULTR_KUBECONFIG"
  value        = base64decode(vultr_kubernetes.mgmt_vultr.kube_config)
  env_slug     = "prod"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/github-actions"
}
