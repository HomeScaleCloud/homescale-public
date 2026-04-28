variable "region" {
  description = "Name of the region to be deployed."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{3}[0-9]$", var.region))
    error_message = "Region must be in format aaa1 (e.g. lon1)."
  }
}

variable "op_service_account_token" {
  description = "1Password Service Account Token"
  type        = string
  sensitive   = true
}

variable "twingate_token" {
  description = "Twingate API Token"
  type        = string
  sensitive   = true
}

variable "twingate_github_actions_service_account_id" {
  description = "GitHub Actions' Twingate Service Account ID"
  type        = string
  sensitive   = true
}

variable "mgmt_cidr" {
  description = "Region mgmt network CIDR"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.mgmt_cidr))
    error_message = "mgmt_cidr must be a valid IPv4 CIDR block, e.g. 10.1.254.0/24."
  }
}
