resource "cloudflare_zero_trust_device_posture_rule" "gateway" {
  account_id = var.cloudflare_account_id
  name       = "Gateway"
  type       = "gateway"
  schedule   = "5m"
}
resource "cloudflare_zero_trust_device_posture_rule" "os_version_windows" {
  account_id = var.cloudflare_account_id
  name       = "OS Version (Windows)"
  type       = "os_version"
  schedule   = "5m"
  match = [{
    platform = "windows"
  }]
  input = {
    operator = ">="
    version  = "10.0.26100"
  }
}
resource "cloudflare_zero_trust_device_posture_rule" "os_version_macos" {
  account_id = var.cloudflare_account_id
  name       = "OS Version (macOS)"
  type       = "os_version"
  schedule   = "5m"
  match = [{
    platform = "mac"
  }]
  input = {
    operator = ">="
    version  = "15.4.1"
  }
}
resource "cloudflare_zero_trust_device_posture_rule" "os_version_ios" {
  account_id = var.cloudflare_account_id
  name       = "OS Version (iOS)"
  type       = "os_version"
  schedule   = "5m"
  match = [{
    platform = "ios"
  }]
  input = {
    operator = ">="
    version  = "18.3.2"
  }
}
resource "cloudflare_zero_trust_device_posture_rule" "os_version_android" {
  account_id = var.cloudflare_account_id
  name       = "OS Version (Android)"
  type       = "os_version"
  schedule   = "5m"
  match = [{
    platform = "android"
  }]
  input = {
    operator = ">="
    version  = "15.0.0"
  }
}
resource "cloudflare_zero_trust_device_posture_rule" "firewall_windows" {
  account_id = var.cloudflare_account_id
  name       = "Firewall (Windows)"
  type       = "firewall"
  schedule   = "5m"
  match = [{
    platform = "windows"
  }]
  input = {
    enabled = true
  }
}
resource "cloudflare_zero_trust_device_posture_rule" "firewall_macos" {
  account_id = var.cloudflare_account_id
  name       = "Firewall (macOS)"
  type       = "firewall"
  schedule   = "5m"
  match = [{
    platform = "mac"
  }]
  input = {
    enabled = true
  }
}
resource "cloudflare_zero_trust_device_posture_rule" "encryption_windows" {
  account_id = var.cloudflare_account_id
  name       = "Disk Encryption (Windows)"
  type       = "disk_encryption"
  schedule   = "5m"
  match = [{
    platform = "windows"
  }]
  input = {
    require_all = false
    check_disks = ["C"]
  }
}
resource "cloudflare_zero_trust_device_posture_rule" "encryption_macos" {
  account_id = var.cloudflare_account_id
  name       = "Disk Encryption (macOS)"
  type       = "disk_encryption"
  schedule   = "5m"
  match = [{
    platform = "mac"
  }]
  input = {
    require_all = false
    check_disks = ["/", "/System/Volumes/Data"]
  }
}
