variable "infisical_github_actions" {
  description = "Infisical machine identity ID for the \"ci\" identity (GitHub Actions OIDC + local-bootstrap universal auth)"
  type        = string
}

variable "infisical_auth_method" {
  description = "Which Infisical provider auth method this run uses — \"oidc\" (CI, default) or \"universal\" (hsctl run terraform -e local)"
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

# Not used by this module's own resources, but Terrakube injects every
# org-level global variable into every workspace's plan regardless — an
# unconsumed -var for an undeclared variable is a hard error.
variable "infisical_org_id" {
  description = "Infisical org UUID (unused here — declared only so Terrakube's org-wide global variable doesn't error as undeclared)"
  type        = string
  default     = ""
}
