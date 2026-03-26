terraform {
  required_providers {
    onepassword = {
      source = "1Password/onepassword"
    }
    twingate = {
      source = "Twingate/twingate"
    }
  }
}

provider "onepassword" {
  service_account_token = var.op_service_account_token
}

provider "twingate" {
  api_token = var.twingate_token
  network   = "homescale"
}
