resource "infisical_secret" "core_kubeconfig" {
  name         = "CORE_KUBECONFIG"
  value        = base64decode(vultr_kubernetes.core.kube_config)
  env_slug     = "prod"
  workspace_id = var.infisical_workspace_id
  folder_path  = "/k8s/automatron"
}
