output "kube_config" {
  value       = base64decode(vultr_kubernetes.mgmt.kube_config)
  description = "Decoded kubeconfig for the mgmt cluster"
  sensitive   = true
}

output "endpoint" {
  value       = vultr_kubernetes.mgmt.endpoint
  description = "Kubernetes API server endpoint"
  sensitive   = true
}
