output "k8s_endpoint" {
  value       = digitalocean_kubernetes_cluster.mgmt.endpoint
  description = "Kubernetes API Endpoint"
  sensitive   = true
}

output "k8s_token" {
  value       = digitalocean_kubernetes_cluster.mgmt.kube_config.0.token
  description = "Kubernetes API Token"
  sensitive   = true
}

output "k8s_ca" {
  value       = base64decode(digitalocean_kubernetes_cluster.mgmt.kube_config.0.cluster_ca_certificate)
  description = "Kubernetes Cluster CA"
  sensitive   = true
}
