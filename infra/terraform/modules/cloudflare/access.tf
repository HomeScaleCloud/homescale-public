locals {
  # exposePublic entries that opt into Cloudflare Access via an `access:` block.
  access_apps = {
    for fqdn, app in local.public_apps :
    fqdn => app.access
    if try(app.access, null) != null
  }
}

data "cloudflare_zero_trust_access_identity_providers" "account" {
  account_id = values(data.cloudflare_zone.app_zones)[0].account.id
}

locals {
  # Resolve each app's allowedIdps (by identity provider name) to Cloudflare IdP IDs.
  # An app that omits allowedIdps resolves to every identity provider configured in
  # the account. allowed_idps is always set explicitly (never left null) so that
  # auto_redirect_to_identity below can skip the IdP picker whenever exactly one
  # provider is in play.
  access_app_idp_ids = {
    for fqdn, access in local.access_apps :
    fqdn => length(try(access.allowedIdps, [])) > 0 ? [
      for name in access.allowedIdps :
      [for idp in data.cloudflare_zero_trust_access_identity_providers.account.result : idp.id if idp.name == name][0]
      ] : [
      for idp in data.cloudflare_zero_trust_access_identity_providers.account.result : idp.id
    ]
  }
}

resource "cloudflare_zero_trust_access_application" "public_app" {
  for_each = local.access_apps

  account_id                = values(data.cloudflare_zone.app_zones)[0].account.id
  name                      = each.key
  domain                    = each.key
  type                      = "self_hosted"
  session_duration          = try(each.value.sessionDuration, null)
  allowed_idps              = local.access_app_idp_ids[each.key]
  auto_redirect_to_identity = length(local.access_app_idp_ids[each.key]) == 1

  policies = [
    {
      name     = "${each.key}-allow"
      decision = "allow"
      include  = [{ everyone = {} }]
    }
  ]
}
