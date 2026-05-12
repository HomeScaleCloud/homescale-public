terraform {
  required_providers {
    onepassword = {
      source = "1Password/onepassword"
    }
    harvester = {
      source = "harvester/harvester"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}

provider "harvester" {
  kubeconfig = data.onepassword_item.harvester_kubeconfig.credential
}

locals {
  kubeconfig = yamldecode(base64decode(data.onepassword_item.harvester_kubeconfig.credential))
  cluster    = local.kubeconfig.clusters[0].cluster
  user       = local.kubeconfig.users[0].user
}

provider "kubernetes" {
  host                   = local.cluster.server
  cluster_ca_certificate = base64decode(local.cluster["certificate-authority-data"])
  client_certificate     = base64decode(local.user["client-certificate-data"])
  client_key             = base64decode(local.user["client-key-data"])
}
