variable "netbird_token" {
  description = "NetBird Service Account Token"
  type        = string
  sensitive   = true
}

variable "op_service_account_token" {
  description = "1Password Service Account Token"
  type        = string
  sensitive   = true
}
