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

# Direct-to-apiserver access — an nginx reverse proxy (apps/netbird-crs's
# kube-apiserver-proxy Deployment) presenting a trusted LetsEncrypt cert and
# forwarding to kubernetes.default.svc.cluster.local, which Kubernetes
# itself already load-balances across every control-plane replica. Whatever
# auth the client presents (e.g. OIDC) is validated by the real apiserver,
# not impersonated from NetBird peer identity like ClusterProxy.
#
# depends_on is load-bearing here, not decorative: this name used to belong
# to kubeapi_proxy (before it was renamed off to nb.k8s.api.*). Without an
# explicit edge, Terraform creates this in parallel with that rename and the
# provider can reject it as a duplicate depending on which request lands
# first — exactly what happened the first time this shipped (two of three
# clusters failed with "already exists", the third won the race).
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
