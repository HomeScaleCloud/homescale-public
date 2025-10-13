resource "kubernetes_namespace" "onepassword" {
  count = (var.cluster_init || var.cluster_init_core_apps) ? 0 : (var.app_onepassword_enabled ? 1 : 0)
  metadata {
    name = "onepassword"
  }
}

resource "kubernetes_namespace" "tailscale" {
  count = (var.cluster_init || var.cluster_init_core_apps) ? 0 : (var.app_tailscale_enabled ? 1 : 0)
  metadata {
    name = "tailscale"
  }
}