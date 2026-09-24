output "kube_config" {
  value       = base64decode(vultr_kubernetes.core.kube_config)
  description = "Decoded kubeconfig for the core cluster"
  sensitive   = true
}

output "endpoint" {
  value       = vultr_kubernetes.core.endpoint
  description = "Kubernetes API server endpoint"
  sensitive   = true
}
