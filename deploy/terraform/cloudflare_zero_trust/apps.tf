resource "cloudflare_zero_trust_access_application" "rancher" {
  name                        = "Rancher"
  domain                      = "rancher.homescale.cloud/dashboard"
  type                        = "self_hosted"
  account_id                  = var.cloudflare_account_id
  allow_authenticate_via_warp = true
  allowed_idps                = [data.cloudflare_zero_trust_access_identity_provider.entra_id.identity_provider_id]
  auto_redirect_to_identity   = true
  app_launcher_visible        = true
  skip_interstitial           = true
  logo_url                    = "https://www.rancher.com/assets/img/brand-guidelines/assets/logos/png/cow/rancher-logo-cow-blue.png"

  destinations = [
    {
      type = "public"
      uri  = "rancher.homescale.cloud/dashboard"
    },
    {
      type = "public"
      uri  = "rancher.homescale.cloud/k8s/clusters"
    },
    {
      type = "public"
      uri  = "rancher.homescale.cloud/api-ui"
    }
  ]

  policies = [
    {
      id         = cloudflare_zero_trust_access_policy.allow_admins.id
      precedence = 1
    },
  ]
}
