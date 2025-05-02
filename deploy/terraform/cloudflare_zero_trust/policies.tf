resource "cloudflare_zero_trust_access_policy" "allow_authenticated" {
  name       = "Allow Authenticated"
  account_id = var.cloudflare_account_id
  decision   = "allow"
  include = [{
    azure_ad = {
      id                   = "dc19df01-8155-4c89-b0ba-a23502f4a99a"
      identity_provider_id = data.cloudflare_zero_trust_access_identity_provider.entra_id.identity_provider_id
    }
  }]
}

resource "cloudflare_zero_trust_access_policy" "allow_all_users" {
  name       = "Allow All Users"
  account_id = var.cloudflare_account_id
  decision   = "allow"
  include = [{
    azure_ad = {
      id                   = "dc19df01-8155-4c89-b0ba-a23502f4a99a"
      identity_provider_id = data.cloudflare_zero_trust_access_identity_provider.entra_id.identity_provider_id
    }
  }]
  require = [
    { group = { id = cloudflare_zero_trust_access_group.posture.id } }
  ]
}

resource "cloudflare_zero_trust_access_policy" "allow_admins" {
  name       = "Allow Admins"
  account_id = var.cloudflare_account_id
  decision   = "allow"
  include = [{
    azure_ad = {
      id                   = "b6d81796-0a24-479b-8eec-4f1fe16512da"
      identity_provider_id = data.cloudflare_zero_trust_access_identity_provider.entra_id.identity_provider_id
    }
  }]
  require = [
    { group = { id = cloudflare_zero_trust_access_group.posture.id } }
  ]
}
