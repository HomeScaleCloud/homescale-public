resource "kubernetes_namespace" "onepassword" {
  count = (var.init_stage_1 || var.init_stage_2) ? 0 : (var.app_onepassword_enabled ? 1 : 0)
  metadata {
    name = "onepassword"
  }
}

resource "kubernetes_namespace" "tailscale" {
  count = (var.init_stage_1 || var.init_stage_2) ? 0 : (var.app_tailscale_enabled ? 1 : 0)
  metadata {
    name = "tailscale"
  }
}
