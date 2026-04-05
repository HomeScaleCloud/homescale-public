terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
    rancher2 = {
      source = "rancher/rancher2"
    }
    twingate = {
      source = "Twingate/twingate"
    }
    onepassword = {
      source = "1Password/onepassword"
    }
  }
}

provider "kubernetes" {
  host                   = var.k8s_endpoint
  token                  = var.k8s_token
  cluster_ca_certificate = var.k8s_ca
}

provider "helm" {
  kubernetes = {
    host                   = var.k8s_endpoint
    token                  = var.k8s_token
    cluster_ca_certificate = var.k8s_ca
  }
}

provider "twingate" {
  api_token = var.twingate_token
  network   = "homescale"
}

provider "rancher2" {
  api_url   = "https://mgmt.homescale.cloud"
  bootstrap = true
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}
