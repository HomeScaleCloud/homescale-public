# Tailnet-wide DNS preference only. Unlike NetBird's per-app zones/records
# (modules/netbird/zones.tf, dns.tf), per-app REDACTED
# hostnames are published by external-dns straight from k8s annotations, not
# managed here.
resource "tailscale_dns_preferences" "this" {
  magic_dns = true
}
