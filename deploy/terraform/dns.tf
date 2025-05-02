resource "cloudflare_dns_record" "github_verify" {
  zone_id = data.onepassword_item.cloudflare_zone_id.credential
  name    = "_gh-homescalecloud-o.homescale.cloud"
  comment = "Domain ownership verification for GitHub"
  content = "064743fb98" #pragma: allowlist secret
  ttl     = 1
  type    = "TXT"
}

resource "cloudflare_dns_record" "azure_verify" {
  zone_id = data.onepassword_item.cloudflare_zone_id.credential
  name    = "homescale.cloud"
  comment = "Domain ownership verification for Azure"
  content = "MS=ms57084443" #pragma: allowlist secret
  ttl     = 3600
  type    = "TXT"
}

resource "cloudflare_dns_record" "exchange_autodiscover" {
  zone_id = data.onepassword_item.cloudflare_zone_id.credential
  name    = "autodiscover.homescale.cloud"
  content = "autodiscover.outlook.com"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "exchange_mx" {
  zone_id  = data.onepassword_item.cloudflare_zone_id.credential
  name     = "homescale.cloud"
  content  = "homescale-cloud.mail.protection.outlook.com"
  priority = 1
  ttl      = 1
  type     = "MX"
}

resource "cloudflare_dns_record" "exchange_spf" {
  zone_id = data.onepassword_item.cloudflare_zone_id.credential
  name    = "homescale.cloud"
  content = "v=spf1 include:spf.protection.outlook.com -all"
  ttl     = 1
  type    = "TXT"
}

resource "cloudflare_dns_record" "exchange_dkim_1" {
  zone_id = data.onepassword_item.cloudflare_zone_id.credential
  name    = "selector1._domainkey.homescale.cloud"
  content = "selector1-homescale-cloud._domainkey.nanni237gmail.onmicrosoft.com"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "exchange_dkim_2" {
  zone_id = data.onepassword_item.cloudflare_zone_id.credential
  name    = "selector2._domainkey.homescale.cloud"
  content = "selector2-homescale-cloud._domainkey.nanni237gmail.onmicrosoft.com"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "intune_registration" {
  zone_id = data.onepassword_item.cloudflare_zone_id.credential
  name    = "enterpriseregistration.homescale.cloud"
  content = "enterpriseregistration.windows.net"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "intune_enrollment" {
  zone_id = data.onepassword_item.cloudflare_zone_id.credential
  name    = "enterpriseenrollment.homescale.cloud"
  content = "enterpriseenrollment-s.manage.microsoft.com"
  ttl     = 1
  type    = "CNAME"
}
