variable "infisical_org_id" {
  description = "Infisical organisation UUID"
  type        = string
}

variable "infisical_github_actions" {
  description = "Infisical machine identity ID for the GitHub Actions OIDC identity"
  type        = string
}

variable "infisical_auth_method" {
  description = "Which Infisical provider auth method this run uses — \"oidc\" (CI, default) or \"universal\" (automatron)"
  type        = string
  default     = "oidc"
  validation {
    condition     = contains(["oidc", "universal"], var.infisical_auth_method)
    error_message = "infisical_auth_method must be \"oidc\" or \"universal\"."
  }
}

variable "infisical_universal_auth_client_id" {
  description = "Universal Auth client ID — only set when infisical_auth_method is \"universal\""
  type        = string
  default     = ""
  sensitive   = true
}

variable "infisical_universal_auth_client_secret" {
  description = "Universal Auth client secret — only set when infisical_auth_method is \"universal\""
  type        = string
  default     = ""
  sensitive   = true
}
