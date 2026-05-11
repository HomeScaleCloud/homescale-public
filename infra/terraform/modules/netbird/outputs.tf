output "netbird_reverse_proxy_clusters_all" {
  value       = data.netbird_reverse_proxy_clusters.all.clusters[0].address
  description = "NetBird Reverse Proxy Endpoints"
  sensitive   = true
}
