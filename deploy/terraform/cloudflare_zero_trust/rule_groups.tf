resource "cloudflare_zero_trust_access_group" "posture_windows" {
  name       = "Device Posture (Windows)"
  account_id = var.cloudflare_account_id
  include = [{
    azure_ad = {
      id                   = "dc19df01-8155-4c89-b0ba-a23502f4a99a"
      identity_provider_id = data.cloudflare_zero_trust_access_identity_provider.entra_id.identity_provider_id
    }
  }]
  require = [
    { device_posture = { integration_uid = cloudflare_zero_trust_device_posture_rule.os_version_windows.id } },
    { device_posture = { integration_uid = cloudflare_zero_trust_device_posture_rule.firewall_windows.id } },
    { device_posture = { integration_uid = cloudflare_zero_trust_device_posture_rule.encryption_windows.id } }
  ]
}

resource "cloudflare_zero_trust_access_group" "posture_macos" {
  name       = "Device Posture (macOS)"
  account_id = var.cloudflare_account_id
  include = [{
    azure_ad = {
      id                   = "dc19df01-8155-4c89-b0ba-a23502f4a99a"
      identity_provider_id = data.cloudflare_zero_trust_access_identity_provider.entra_id.identity_provider_id
    }
  }]
  require = [
    { device_posture = { integration_uid = cloudflare_zero_trust_device_posture_rule.os_version_macos.id } },
    { device_posture = { integration_uid = cloudflare_zero_trust_device_posture_rule.firewall_macos.id } },
    { device_posture = { integration_uid = cloudflare_zero_trust_device_posture_rule.encryption_macos.id } }
  ]
}

resource "cloudflare_zero_trust_access_group" "posture_ios" {
  name       = "Device Posture (iOS)"
  account_id = var.cloudflare_account_id
  include = [{
    azure_ad = {
      id                   = "dc19df01-8155-4c89-b0ba-a23502f4a99a"
      identity_provider_id = data.cloudflare_zero_trust_access_identity_provider.entra_id.identity_provider_id
    }
  }]
  require = [
    { device_posture = { integration_uid = cloudflare_zero_trust_device_posture_rule.os_version_ios.id } }
  ]
}

resource "cloudflare_zero_trust_access_group" "posture_android" {
  name       = "Device Posture (Android)"
  account_id = var.cloudflare_account_id
  include = [{
    azure_ad = {
      id                   = "dc19df01-8155-4c89-b0ba-a23502f4a99a"
      identity_provider_id = data.cloudflare_zero_trust_access_identity_provider.entra_id.identity_provider_id
    }
  }]
  require = [
    { device_posture = { integration_uid = cloudflare_zero_trust_device_posture_rule.os_version_android.id } }
  ]
}

resource "cloudflare_zero_trust_access_group" "posture" {
  name       = "Device Posture"
  account_id = var.cloudflare_account_id
  include = [
    { group = { id = cloudflare_zero_trust_access_group.posture_windows.id } },
    { group = { id = cloudflare_zero_trust_access_group.posture_macos.id } },
    { group = { id = cloudflare_zero_trust_access_group.posture_ios.id } },
    { group = { id = cloudflare_zero_trust_access_group.posture_android.id } }
  ]
  require = [
    { device_posture = { integration_uid = cloudflare_zero_trust_device_posture_rule.gateway.id } }
  ]
}
