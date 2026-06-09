variable "infisical_org_id" {
  description = "Infisical organisation UUID"
  type        = string
}

variable "infisical_github_actions" {
  description = "Infisical machine identity ID for the GitHub Actions OIDC identity"
  type        = string
}

variable "netbird_token" {
  description = "NetBird service account token"
  type        = string
  sensitive   = true
}
