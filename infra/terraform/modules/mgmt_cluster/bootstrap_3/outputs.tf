output "rancher_token" {
  value       = rancher2_bootstrap.mgmt.token
  description = "Rancher API Token"
  sensitive   = true
}
