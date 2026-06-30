terraform {
  required_providers {
    vultr = {
      source = "vultr/vultr"
    }
    infisical = {
      source = "infisical/infisical"
    }
  }
}

provider "vultr" {
  api_key = var.vultr_api_key
}
