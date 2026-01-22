resource "kubernetes_namespace" "onepassword" {
  count = (var.init_stage_1 || var.init_stage_2) ? 0 : 1
  metadata {
    name = "onepassword"
  }
}

resource "kubernetes_namespace" "tailscale" {
  count = (var.init_stage_1 || var.init_stage_2) ? 0 : 1
  metadata {
    name = "tailscale"
  }
}
