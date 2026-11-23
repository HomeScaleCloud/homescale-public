terraform {
  required_providers {
    terrakube = {
      source  = "registry.terraform.io/terrakube-io/terrakube"
      version = "0.34.0"
    }
  }
}

provider "terrakube" {
  endpoint = "https://REDACTED"
  token    = try(file("/var/run/secrets/kubernetes.io/serviceaccount/token"), null)
}
