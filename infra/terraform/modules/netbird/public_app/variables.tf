variable "name" {
  description = "App name."
  type        = string
}

variable "cluster" {
  description = "Name of the cluster instance to expose."
  type        = string
}

variable "domain" {
  description = "Domain for the app."
  type        = string
}

variable "fqdn" {
  description = "FQDN to expose the app at."
  type        = string
}

variable "peer_groups" {
  type        = list(string)
  description = "List of NetBird peer groups that publish the app."
}

variable "protocol" {
  description = "Protocol for the app."
  type        = string
}

variable "port" {
  description = "Port for the app."
  type        = string
}

variable "infisical_workspace_id" {
  description = "Infisical project/workspace UUID"
  type        = string
}
