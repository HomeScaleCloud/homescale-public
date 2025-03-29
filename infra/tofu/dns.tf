resource "cloudflare_dns_record" "github_verify" {
  zone_id = var.cloudflare_zone_id
  name    = "_github-challenge-HomeScaleCloud-org.homescale.cloud"
  comment = "Domain ownership verification for GitHub"
  content = "e2628155b4"
  ttl     = 1
  type    = "TXT"
}

resource "cloudflare_dns_record" "smtpgo_1" {
  zone_id = var.cloudflare_zone_id
  name    = "em569112.homescale.cloud"
  content = "return.smtp2go.net"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "smtpgo_2" {
  zone_id = var.cloudflare_zone_id
  name    = "email-track.homescale.cloud"
  content = "track.smtp2go.net"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "smtpgo_3" {
  zone_id = var.cloudflare_zone_id
  name    = "s569112._domainkey.homescale.cloud"
  content = "dkim.smtp2go.net"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "protonmail_domainkey_1" {
  zone_id = var.cloudflare_zone_id
  name    = "protonmail._domainkey.homescale.cloud"
  content = "protonmail.domainkey.dhbmfi47x6nlcfx52qhqroqsbgn77curmn2yz4mckm6stp7jytj3a.domains.proton.ch"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "protonmail_domainkey_2" {
  zone_id = var.cloudflare_zone_id
  name    = "protonmail2._domainkey.homescale.cloud"
  content = "protonmail2.domainkey.dhbmfi47x6nlcfx52qhqroqsbgn77curmn2yz4mckm6stp7jytj3a.domains.proton.ch"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "protonmail_domainkey_3" {
  zone_id = var.cloudflare_zone_id
  name    = "protonmail3._domainkey.homescale.cloud"
  content = "protonmail3.domainkey.dhbmfi47x6nlcfx52qhqroqsbgn77curmn2yz4mckm6stp7jytj3a.domains.proton.ch"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "protonmail_mx_1" {
  zone_id  = var.cloudflare_zone_id
  name     = "homescale.cloud"
  content  = "mail.protonmail.ch"
  priority = 10
  ttl      = 1
  type     = "MX"
}

resource "cloudflare_dns_record" "protonmail_mx_2" {
  zone_id  = var.cloudflare_zone_id
  name     = "homescale.cloud"
  content  = "mailsec.protonmail.ch"
  priority = 20
  ttl      = 1
  type     = "MX"
}

resource "cloudflare_dns_record" "protonmail_spf" {
  zone_id = var.cloudflare_zone_id
  name    = "homescale.cloud"
  content = "v=spf1 include:_spf.protonmail.ch ~all"
  ttl     = 1
  type    = "TXT"
}

resource "cloudflare_dns_record" "protonmail_verify" {
  zone_id = var.cloudflare_zone_id
  name    = "homescale.cloud"
  content = "protonmail-verification=9eddebf7a991dd53bf71aebe5bdc71672527e6a4"
  ttl     = 1
  type    = "TXT"
}

resource "cloudflare_dns_record" "status" {
  zone_id = var.cloudflare_zone_id
  name    = "status.homescale.cloud"
  content = "statuspage.betteruptime.com"
  ttl     = 1
  type    = "CNAME"
}
