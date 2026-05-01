terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

provider "digitalocean" {
  token = var.digitalocean_token
}

provider "helm" {
  kubernetes = {
    host                   = digitalocean_kubernetes_cluster.mgmt.endpoint
    token                  = digitalocean_kubernetes_cluster.mgmt.kube_config.0.token
    cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.mgmt.kube_config.0.cluster_ca_certificate)
  }
}
