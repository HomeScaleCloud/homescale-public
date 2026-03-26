variable "region" {
  description = "Name of the region to be deployed."
  type        = string

  validation {
    condition     = can(regex("^[A-Z]{3}[0-9]$", var.region))
    error_message = "Region must be in format AAA1 (e.g., BOA1, LON1, BRS1)."
  }
}

variable "op_service_account_token" {
  description = "1Password Service Account Token"
  type        = string
  sensitive   = true
}
