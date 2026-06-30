resource "netbird_dns_record" "omni" {
  for_each = toset(["mgmt", "mgmt-vultr"])

  zone_id = netbird_dns_zone.cluster[each.key].id
  name    = "omni.${each.key}xxx"
  type    = "CNAME"
  content = "api.omni.${each.key}xxx"
  ttl     = 300
}

resource "netbird_dns_record" "kubeapi" {
  for_each = netbird_dns_zone.cluster

  zone_id = each.value.id
  name    = "k8s.${each.key}xxx"
  type    = "CNAME"
  content = "${each.key}xxx"
  ttl     = 300
}

resource "netbird_dns_zone" "metrics" {
  name                 = "xxx"
  domain               = "xxx"
  enabled              = true
  enable_search_domain = false
  distribution_groups  = [data.netbird_group.all.id]
}

resource "netbird_dns_record" "grafana" {
  zone_id = netbird_dns_zone.metrics.id
  name    = "xxx"
  type    = "CNAME"
  content = "xxx"
  ttl     = 300
}

resource "netbird_dns_record" "alertmanager" {
  zone_id = netbird_dns_zone.metrics.id
  name    = "xxx"
  type    = "CNAME"
  content = "xxx"
  ttl     = 300
}

resource "netbird_dns_record" "prometheus" {
  zone_id = netbird_dns_zone.metrics.id
  name    = "xxx"
  type    = "CNAME"
  content = "xxx"
  ttl     = 300
}

resource "netbird_dns_record" "loki" {
  zone_id = netbird_dns_zone.metrics.id
  name    = "xxx"
  type    = "CNAME"
  content = "xxx"
  ttl     = 300
}
