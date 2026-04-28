terraform {
  required_providers {
    onepassword = {
      source = "1Password/onepassword"
    }
    harvester = {
      source = "harvester/harvester"
    }
  }
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}

provider "harvester" {
  kubeconfig = data.onepassword_item.harvester_kubeconfig.credential
}
