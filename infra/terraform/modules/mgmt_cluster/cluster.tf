resource "vultr_kubernetes" "mgmt" {
  label   = "mgmt"
  region  = var.region
  version = var.k8s_version

  oidc_issuer_url     = var.oidc_issuer_url
  oidc_client_id      = var.oidc_client_id
  oidc_username_claim = var.oidc_username_claim
  oidc_groups_claim   = var.oidc_groups_claim

  node_pools {
    label         = "mgmt-node"
    plan          = var.node_plan
    node_quantity = var.node_count
    auto_scaler   = false
  }
}
