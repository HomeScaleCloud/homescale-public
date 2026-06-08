variable "infisical_org_id" {
  description = "Infisical organisation UUID (find in Org Settings → General)"
  type        = string
}

variable "infisical_github_actions" {
  description = "Infisical machine identity ID for the GitHub Actions OIDC identity — used by Terraform and any workflow needing write access (TF_VAR_infisical_github_actions)"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token — fetched from Infisical /ci via GitHub Actions OIDC"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for REDACTED — fetched from Infisical /ci via GitHub Actions OIDC"
  type        = string
}

variable "digitalocean_token" {
  description = "DigitalOcean API token — fetched from Infisical /ci via GitHub Actions OIDC"
  type        = string
  sensitive   = true
}

variable "netbird_token" {
  description = "NetBird service account token — fetched from Infisical /ci via GitHub Actions OIDC"
  type        = string
  sensitive   = true
}

variable "argocd_deploy_key" {
  description = "Base64-encoded SSH private key for ArgoCD to pull from GitHub — fetched from Infisical /k8s/argocd via GitHub Actions OIDC"
  type        = string
  sensitive   = true
}
