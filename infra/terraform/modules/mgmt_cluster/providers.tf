terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
    onepassword = {
      source = "1Password/onepassword"
    }
    rancher2 = {
      source = "rancher/rancher2"
    }
    twingate = {
      source = "Twingate/twingate"
    }
  }
}

provider "digitalocean" {
  token = var.digitalocean_token
}

provider "kubernetes" {
  host                   = digitalocean_kubernetes_cluster.mgmt.endpoint
  token                  = digitalocean_kubernetes_cluster.mgmt.kube_config.0.token
  cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.mgmt.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
    host                   = digitalocean_kubernetes_cluster.mgmt.endpoint
    token                  = digitalocean_kubernetes_cluster.mgmt.kube_config.0.token
    cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.mgmt.kube_config.0.cluster_ca_certificate)
  }
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}

provider "twingate" {
  api_token = var.twingate_token
  network   = "homescale"
}

provider "rancher2" {
  alias     = "bootstrap"
  api_url   = "https://mgmt.tempel-carp.ts.net"
  bootstrap = true
}

provider "rancher2" {
  api_url   = "https://mgmt.tempel-carp.ts.net"
  token_key = rancher2_bootstrap.mgmt[0].token
}
