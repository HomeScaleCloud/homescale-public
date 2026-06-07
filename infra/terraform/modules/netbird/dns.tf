resource "netbird_dns_record" "omni" {
  zone_id = netbird_dns_zone.cluster["mgmt"].id
  name    = "REDACTED"
  type    = "CNAME"
  content = "REDACTED"
  ttl     = 300
}
