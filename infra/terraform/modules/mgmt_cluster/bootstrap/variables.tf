variable "k8s_endpoint" {
  description = "mgmt cluster k8s endpoint"
  type        = string
  sensitive   = true
}

variable "k8s_token" {
  description = "mgmt cluster k8s token"
  type        = string
  sensitive   = true
}

variable "k8s_ca" {
  description = "mgmt cluster k8s CA"
  type        = string
  sensitive   = true
}

variable "op_service_account_token" {
  description = "1Password Service Account Token"
  type        = string
  sensitive   = true
}
