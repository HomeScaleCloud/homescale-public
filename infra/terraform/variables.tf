variable "infisical_org_id" {
  description = "Infisical organisation UUID (find in Org Settings → General)"
  type        = string
}

variable "infisical_github_actions" {
  description = "Infisical machine identity ID for the GitHub Actions OIDC identity (TF_VAR_infisical_github_actions)"
  type        = string
}

variable "netbird_token" {
  description = "NetBird service account token (NETBIRD_SA_TOKEN)"
  type        = string
  sensitive   = true
}
