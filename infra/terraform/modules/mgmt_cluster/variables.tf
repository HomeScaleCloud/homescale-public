variable "region" {
  description = "Name of the region the cluster resides in"
  type        = string
}

variable "k8s_version" {
  description = "Kubernetes version to be used (options vary by platform)."
  type        = string
}

variable "digitalocean_token" {
  description = "DigitalOcean API Token"
  type        = string
  sensitive   = true
}

variable "infisical_workspace_id" {
  description = "Infisical project/workspace UUID"
  type        = string
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
