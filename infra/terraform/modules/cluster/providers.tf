terraform {
  required_providers {
    # kubernetes = {
    #   source  = "hashicorp/kubernetes"
    # }
    onepassword = {
      source = "1Password/onepassword"
    }
    tailscale = {
      source = "tailscale/tailscale"
    }
    talos = {
      source = "siderolabs/talos"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

provider "kubernetes" {
  host                   = data.talos_machine_configuration.controlplane.cluster_endpoint
  cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.cluster.kubernetes_client_configuration.ca_certificate)
  client_certificate     = base64decode(talos_cluster_kubeconfig.cluster.kubernetes_client_configuration.client_certificate)
  client_key             = base64decode(talos_cluster_kubeconfig.cluster.kubernetes_client_configuration.client_key)
}

provider "helm" {
  kubernetes = {
    host                   = data.talos_machine_configuration.controlplane.cluster_endpoint
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.cluster.kubernetes_client_configuration.ca_certificate)
    client_certificate     = base64decode(talos_cluster_kubeconfig.cluster.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.cluster.kubernetes_client_configuration.client_key)
  }
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}

provider "tailscale" {
  tailnet             = "homescale.cloud"
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
}
