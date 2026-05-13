data "onepassword_vault" "k8s" {
  name = "k8s"
}

resource "onepassword_item" "netbird_region_setup_key" {
  vault    = data.onepassword_vault.k8s.uuid
  title    = "netbird-${var.region}-setup-key"
  password = netbird_setup_key.region_router.key
}
