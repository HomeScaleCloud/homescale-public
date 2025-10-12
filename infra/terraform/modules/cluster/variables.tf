variable "cluster" {
  description = "Name of the cluster to deploy"
  type        = string
}

variable "region" {
  description = "Name of the region the cluster resides in"
  type        = string
}

variable "platform" {
  description = "Node platform to be used (metal, digital-ocean, etc)"
  type        = string
}

variable "cluster_init" {
  description = "Enable for the first apply of this cluster (disable after first apply to deploy apps)"
  type        = bool
  default     = false
}

variable "gateway" {
  description = "IPv4 gateway to be used by nodes"
  type        = string
  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.gateway))
    error_message = "gateway must be a valid IPv4 address."
  }
}

variable "nfs_server" {
  description = "IP address of NFS server to use"
  type        = string
  default     = "null"
}

variable "nfs_path" {
  description = "Path on NFS server to provision PVCs within"
  type        = string
  default     = "null"
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
  default     = "v1.11.2"
}

variable "talos_disk_selector" {
  description = "Selector for the disk to install Talos Linux to"
  type        = map(number)
}

# apps
variable "app_cert_manager_enabled" {
  type    = bool
  default = true
}

variable "app_cert_manager_crs_enabled" {
  type    = bool
  default = true
}

variable "app_external_dns_enabled" {
  type    = bool
  default = true
}

variable "app_external_dns_crs_enabled" {
  type    = bool
  default = true
}

variable "app_generic_device_plugin_enabled" {
  type    = bool
  default = true
}

variable "app_home_assistant_enabled" {
  type    = bool
  default = false
}

variable "app_homepage_enabled" {
  type    = bool
  default = false
}

variable "app_ingress_nginx_enabled" {
  type    = bool
  default = true
}

variable "app_librespeed_enabled" {
  type    = bool
  default = true
}

variable "app_metrics_enabled" {
  type    = bool
  default = true
}

variable "app_node_feature_discovery_enabled" {
  type    = bool
  default = true
}

variable "app_nfs_provisioner_enabled" {
  type    = bool
  default = false
}

variable "app_onepassword_enabled" {
  type    = bool
  default = true
}

variable "app_rbac_enabled" {
  type    = bool
  default = true
}

variable "app_rook_ceph_enabled" {
  type    = bool
  default = false
}

variable "app_tailscale_enabled" {
  type    = bool
  default = true
}

variable "app_trivy_operator_enabled" {
  type    = bool
  default = true
}