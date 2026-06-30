output "kube_config" {
  value       = base64decode(vultr_kubernetes.mgmt_vultr.kube_config)
  description = "Decoded kubeconfig for the mgmt-vultr cluster"
  sensitive   = true
}

output "endpoint" {
  value       = vultr_kubernetes.mgmt_vultr.endpoint
  description = "Kubernetes API server endpoint"
  sensitive   = true
}
