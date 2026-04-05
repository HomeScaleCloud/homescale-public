variable "twingate_token" {
  description = "Twingate API Token"
  type        = string
  sensitive   = true
}

variable "op_service_account_token" {
  description = "1Password Service Account Token"
  type        = string
  sensitive   = true
}

variable "k8s_endpoint" {
  description = "Kubernetes API Endpoint"
  type        = string
  sensitive   = true
}

variable "k8s_token" {
  description = "Kubernetes API Token"
  type        = string
  sensitive   = true
}

variable "k8s_ca" {
  description = "Kubernetes Cluster CA"
  type        = string
  sensitive   = true
}
