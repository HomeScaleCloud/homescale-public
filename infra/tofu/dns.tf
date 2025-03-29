resource "cloudflare_dns_record" "github_verify" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  comment = "Domain ownership verification for GitHub"
  content = "e2628155b4"
  ttl     = 1
  type    = "TXT"
}

resource "cloudflare_dns_record" "smtpgo_1" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "return.smtp2go.net"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "smtpgo_2" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "track.smtp2go.net"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "smtpgo_3" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "dkim.smtp2go.net"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "protonmail_domainkey_1" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "protonmail.domainkey.dhbmfi47x6nlcfx52qhqroqsbgn77curmn2yz4mckm6stp7jytj3a.domains.proton.ch"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "protonmail_domainkey_2" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "protonmail2.domainkey.dhbmfi47x6nlcfx52qhqroqsbgn77curmn2yz4mckm6stp7jytj3a.domains.proton.ch"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "protonmail_domainkey_3" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "protonmail3.domainkey.dhbmfi47x6nlcfx52qhqroqsbgn77curmn2yz4mckm6stp7jytj3a.domains.proton.ch"
  ttl     = 1
  type    = "CNAME"
}

resource "cloudflare_dns_record" "protonmail_mx_1" {
  zone_id  = var.cloudflare_zone_id
  name     = "xxx"
  content  = "mail.protonmail.ch"
  priority = 10
  ttl      = 1
  type     = "MX"
}

resource "cloudflare_dns_record" "protonmail_mx_2" {
  zone_id  = var.cloudflare_zone_id
  name     = "xxx"
  content  = "mailsec.protonmail.ch"
  priority = 20
  ttl      = 1
  type     = "MX"
}

resource "cloudflare_dns_record" "protonmail_spf" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "v=spf1 include:_spf.protonmail.ch ~all"
  ttl     = 1
  type    = "TXT"
}

resource "cloudflare_dns_record" "protonmail_verify" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "protonmail-verification=9eddebf7a991dd53bf71aebe5bdc71672527e6a4"
  ttl     = 1
  type    = "TXT"
}

resource "cloudflare_dns_record" "status" {
  zone_id = var.cloudflare_zone_id
  name    = "xxx"
  content = "statuspage.betteruptime.com"
  ttl     = 1
  type    = "CNAME"
}
