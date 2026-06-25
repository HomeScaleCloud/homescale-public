resource "cloudflare_dns_record" "app" {
  zone_id = data.infisical_secrets.github_actions.secrets["CLOUDFLARE_ZONE_ID"].value
  name    = var.fqdn
  content = "${var.name}.${var.domain}"
  ttl     = 1
  type    = "CNAME"
}
