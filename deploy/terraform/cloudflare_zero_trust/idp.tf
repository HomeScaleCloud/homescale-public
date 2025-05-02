data "cloudflare_zero_trust_access_identity_provider" "entra_id" {
  identity_provider_id = "0576db37-46c9-4da2-93b6-11f804c1ef26"
  account_id           = var.cloudflare_account_id
}
