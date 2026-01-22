variable "cluster" {
  description = "Name of the cluster to deploy"
  type        = string
}

variable "region" {
  description = "Name of the region the cluster resides in"
  type        = string
}

variable "env" {
  description = "Security environment of the cluster (prod, lab, etc)"
  type        = string
  default     = "lab"
}

variable "platform" {
  description = "Cluster platform to be used (harvester, digitalocean, kubeconfig, etc)."
  type        = string
}

variable "version" {
  description = "Kubernetes version to be used (options vary by platform)."
  type        = string
}

variable "init_stage_1" {
  description = "Enable for the first apply to bootstrap nodes + k8s."
  type        = bool
  default     = false
}

variable "init_stage_2" {
  description = "Enable for the second apply to bootstrap core apps (CNI, ArgoCD, etc)"
  type        = bool
  default     = false
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
