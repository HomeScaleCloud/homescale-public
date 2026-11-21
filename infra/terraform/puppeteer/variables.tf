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

variable "vcs_connection_name" {
  description = "Name of the existing Terrakube VCS connection to GitHub (Settings → Version Control in the Terrakube UI) that already backs the \"legacy\" workspace"
  type        = string
}

variable "organization_template_name" {
  description = "Name of the existing Terrakube organization template each managed workspace should run under (whatever template \"legacy\" already uses)"
  type        = string
}

variable "terraform_version" {
  description = "Terraform CLI version each managed workspace runs (whatever version \"legacy\" is currently configured with in the Terrakube UI)"
  type        = string
}

variable "repository" {
  description = "Git URL puppeteer-managed workspaces check out (this repo)"
  type        = string
  default     = "https://github.com/HomeScaleCloud/homescale.git"
}

variable "repository_branch" {
  description = "Branch puppeteer-managed workspaces track"
  type        = string
  default     = "main"
}
