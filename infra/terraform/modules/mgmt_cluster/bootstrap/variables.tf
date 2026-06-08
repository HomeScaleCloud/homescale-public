variable "k8s_endpoint" {
  description = "mgmt cluster k8s endpoint"
  type        = string
  sensitive   = true
}

variable "k8s_token" {
  description = "mgmt cluster k8s token"
  type        = string
  sensitive   = true
}

variable "k8s_ca" {
  description = "mgmt cluster k8s CA"
  type        = string
  sensitive   = true
}

variable "infisical_k8s_operator_client_id" {
  description = "Client ID for the k8s-mgmt-operator Infisical identity"
  type        = string
}

variable "infisical_k8s_operator_client_secret" {
  description = "Client secret for the k8s-mgmt-operator Infisical identity"
  type        = string
  sensitive   = true
}

variable "argocd_deploy_key" {
  description = "Base64-encoded SSH private key for ArgoCD to pull from GitHub"
  type        = string
  sensitive   = true
}
