# ClusterProxy access (impersonates by connecting NetBird peer identity —
# suitable for humans/CI as individual peers, not for a shared backend like
# Headlamp serving many users; see the "Direct cluster API access" section
# in docs/architecture/networking.md). Kept on nb.k8s.api.* — automations
# (CI) still use this; k8s.api.* below is now the direct-to-apiserver path.
resource "netbird_dns_record" "kubeapi_proxy" {
  for_each = netbird_dns_zone.cluster

  zone_id = each.value.id
  name    = "nb.k8s.api.${each.key}REDACTED"
  type    = "CNAME"
  content = "${each.key}REDACTED"
  ttl     = 300
}

# Direct-to-apiserver access — reaches the cluster's real kube-apiserver
# (apps/netbird-crs/templates/networkresource-apiserver.yaml), so whatever
# auth the client presents (e.g. OIDC) is validated by that apiserver
# itself, not impersonated from NetBird peer identity like ClusterProxy.
resource "netbird_dns_record" "kubeapi_direct" {
  for_each = netbird_dns_zone.cluster

  zone_id = each.value.id
  name    = "k8s.api.${each.key}REDACTED"
  type    = "CNAME"
  content = "kube-apiserver-direct.kube-system.${each.key}REDACTED"
  ttl     = 300
}

resource "netbird_dns_record" "app_cname" {
  for_each = local.app_netbird_cnames

  zone_id = netbird_dns_zone.app[each.value.zone].id
  name    = each.value.fqdn
  type    = "CNAME"
  content = "${each.value.service}.${each.value.namespace}.${each.value.cluster}REDACTED"
  ttl     = 300
}
