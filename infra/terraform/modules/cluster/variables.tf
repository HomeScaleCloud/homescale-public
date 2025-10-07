variable "region" {
  description = "Region name to deploy to"
  type        = string
  default = "dev"
  validation {
    condition     = can(regex("^(dev|[a-z]{3}[0-9]{1,2})$", var.region))
    error_message = "Region must be 'dev' or 3 lowercase letters followed by 1 or 2 digits (e.g., boa1, lon21)."
  }
}

variable "kubeconfig" {
  description = "Kubeconfig to use for app deployment"
  type        = string
  sensitive   = true
}

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