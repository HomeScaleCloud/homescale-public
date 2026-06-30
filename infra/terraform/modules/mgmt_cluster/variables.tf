variable "vultr_api_key" {
  description = "Vultr API key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Vultr region ID for the cluster (e.g. lhr for London)"
  type        = string
}

variable "k8s_version" {
  description = "Kubernetes version string as returned by the Vultr API (e.g. v1.34.8+2). Check available versions at https://api.vultr.com/v2/kubernetes/versions"
  type        = string
}

variable "node_count" {
  description = "Number of worker nodes in the default node pool"
  type        = number
  default     = 2
}

variable "node_plan" {
  description = "Vultr plan ID for worker nodes"
  type        = string
  default     = "vc2-4c-8gb"
}

variable "infisical_workspace_id" {
  description = "Infisical project/workspace UUID"
  type        = string
}
