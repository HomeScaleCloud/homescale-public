variable "region" {
  description = "Name of the region the cluster resides in"
  type        = string
}

variable "k8s_version" {
  description = "Kubernetes version to be used (options vary by platform)."
  type        = string
}

variable "digitalocean_token" {
  description = "DigitalOcean API Token"
  type        = string
  sensitive   = true
}
