resource "netbird_dns_record" "omni" {
  zone_id = netbird_dns_zone.cluster["mgmt"].id
  name    = "xxx"
  type    = "CNAME"
  content = "xxx"
  ttl     = 300
}
