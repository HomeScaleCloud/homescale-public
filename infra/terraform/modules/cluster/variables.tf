variable "cluster" {
  description = "Name of the cluster to deploy"
  type        = string
}

# variable "kubeconfig" {
#   description = "Kubeconfig to use for app deployment"
#   type        = string
#   sensitive   = true
# }

variable "op_service_account_token" {
  description = "1Password Service Account Token"
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

variable "nodes" {
  description = "List of node IPs"
  type        = list(string)
  validation {
    condition     = length(var.nodes) > 0
    error_message = "At least one node must be specified."
  }
}

variable "vip" {
  description = "Virtual IP Address (VIP) to be used for k8s controlplane"
  type        = string
  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.vip))
    error_message = "VIP must be a valid IPv4 address."
  }
}