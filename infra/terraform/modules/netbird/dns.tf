resource "netbird_dns_record" "kubeapi_proxy" {
  for_each = netbird_dns_zone.cluster

  zone_id = each.value.id
  name    = "nb.k8s.api.${each.key}REDACTED"
  type    = "CNAME"
  content = "${each.key}REDACTED"
  ttl     = 300
}

resource "netbird_dns_record" "kubeapi_direct" {
  for_each = netbird_dns_zone.cluster

  zone_id = each.value.id
  name    = "k8s.api.${each.key}REDACTED"
  type    = "CNAME"
  content = "kube-apiserver-proxy.netbird.${each.key}REDACTED"
  ttl     = 300

  depends_on = [netbird_dns_record.kubeapi_proxy]
}

resource "netbird_dns_record" "app_cname" {
  for_each = local.app_netbird_cnames

  zone_id = netbird_dns_zone.app[each.value.zone].id
  name    = each.value.fqdn
  type    = "CNAME"
  content = "${each.value.service}.${each.value.namespace}.${each.value.cluster}REDACTED"
  ttl     = 300
}
