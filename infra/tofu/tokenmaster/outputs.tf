output "project_id" {
  description = "Infisical project ID — passed to other modules as infisical_workspace_id"
  value       = data.infisical_projects.homescale.id
}

output "k8s_operator_client_id" {
  value = infisical_identity_universal_auth_client_secret.k8s_operator.client_id
}

output "k8s_operator_client_secret" {
  value     = infisical_identity_universal_auth_client_secret.k8s_operator.client_secret
  sensitive = true
}
