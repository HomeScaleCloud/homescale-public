terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
    onepassword = {
      source = "1Password/onepassword"
    }
    tailscale = {
      source = "tailscale/tailscale"
    }
    rancher2 = {
      source = "rancher/rancher2"
    }
  }
}

provider "kubernetes" {
  host                   = digitalocean_kubernetes_cluster.mgmt.endpoint
  token = digitalocean_kubernetes_cluster.mgmt.kube_config.0.token
  cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.mgmt.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes = {
  host                   = digitalocean_kubernetes_cluster.mgmt.endpoint
  token = digitalocean_kubernetes_cluster.mgmt.kube_config.0.token
  cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.mgmt.kube_config.0.cluster_ca_certificate)
  }
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}

provider "tailscale" {
  tailnet             = var.tailscale_tailnet
  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret
}
