resource "vultr_kubernetes" "mgmt_vultr" {
  label   = "mgmt-vultr"
  region  = var.region
  version = var.k8s_version

  node_pools {
    label         = "mgmt-vultr-node"
    plan          = var.node_plan
    node_quantity = var.node_count
    auto_scaler   = false
  }
}
