variable "netbird_token" {
  description = "NetBird Service Account Token"
  type        = string
  sensitive   = true
}

variable "infisical_workspace_id" {
  description = "Infisical project/workspace UUID"
  type        = string
}
