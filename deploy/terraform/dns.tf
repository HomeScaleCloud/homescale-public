resource "cloudflare_dns_record" "github_verify" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  comment = "Domain ownership verification for GitHub"
  content = "064743fb98" #pragma: allowlist secret
  ttl     = 1
  type    = "TXT"
}

resource "cloudflare_dns_record" "azure_verify" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  comment = "Domain ownership verification for Azure"
  content = "MS=ms57084443" #pragma: allowlist secret
  ttl     = 3600
  type    = "TXT"
}

resource "cloudflare_dns_record" "exchange_autodiscover" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "autodiscover.outlook.com"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "exchange_mx" {
  zone_id  = var.cloudflare_zone_id
  name     = "xxx"
  content  = "homescale-cloud.mail.protection.outlook.com"
  priority = 1
  ttl      = 1
  type     = "MX"
}

resource "cloudflare_dns_record" "exchange_spf" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "v=spf1 include:spf.protection.outlook.com -all"
  ttl     = 1
  type    = "TXT"
}

resource "cloudflare_dns_record" "exchange_dkim_1" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "selector1-homescale-cloud._domainkey.nanni237gmail.onmicrosoft.com"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "exchange_dkim_2" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "selector2-homescale-cloud._domainkey.nanni237gmail.onmicrosoft.com"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "intune_registration" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "enterpriseregistration.windows.net"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "intune_enrollment" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "enterpriseenrollment-s.manage.microsoft.com"
  ttl     = 1
  type    = "CNAME"
}
