variable "region" {
  description = "Name of the region the cluster resides in"
  type        = string
}

variable "platform" {
  description = "Cluster platform to be used (harvester, digitalocean, aks, etc)."
  type        = string
}

variable "version" {
  description = "Kubernetes version to be used (options vary by platform)."
  type        = string
}

variable "op_service_account_token" {
  description = "1Password Service Account Token"
  type        = string
  sensitive   = true
}

variable "tailscale_tailnet" {
  description = "Tailscale Tailnet Name"
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth Client ID"
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth Client Secret"
  type        = string
  sensitive   = true
}     
