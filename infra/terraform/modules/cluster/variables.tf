variable "cluster" {
  description = "Name of the cluster to deploy"
  type        = string
}

variable "region" {
  description = "Name of the region the cluster resides in"
  type        = string
}

variable "gateway" {
  description = "IPv4 gateway to be used by nodes"
  type        = string
  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.gateway))
    error_message = "gateway must be a valid IPv4 address."
  }
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

variable "controlplane_nodes" {
  description = "List of controlplane node IPs"
  type        = list(string)
  validation {
    condition     = length(var.controlplane_nodes) > 0
    error_message = "At least one node must be specified."
  }
}

locals {
  controlplane_nodes = {
    for idx, ip in var.controlplane_nodes :
    idx + 1 => ip
  }
}

variable "controlplane_vip" {
  description = "Virtual IP Address (VIP) to be used for k8s controlplane"
  type        = string
  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.controlplane_vip))
    error_message = "VIP must be a valid IPv4 address."
  }
}

variable "workloads_on_controlplane" {
  description = "Whether to allow workload pods to run on controlplane nodes"
  type        = bool
  default     = false
}

variable "store_kubeconfig" {
  description = "Whether to store kubeconfig in 1Password"
  type        = bool
  default     = false
}

variable "store_talosconfig" {
  description = "Whether to store talosconfig in 1Password"
  type        = bool
  default     = false
}

variable "talos_version" {
  description = "Version of Talos Linux to deploy"
  type        = string
  default     = "1.11.2"
}