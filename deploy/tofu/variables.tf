variable "cloudflare_token" {
  description = "Cloudflare API Token"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}

variable "vultr_token" {
  description = "Vultr API Token"
  type        = string
  sensitive   = true
}

variable "digitalocean_token" {
  description = "DigitalOcean API Token"
  type        = string
  sensitive   = true
}

variable "digitalocean_spaces_id" {
  description = "DigitalOcean Spaces Access Key ID"
  type        = string
  sensitive   = true
}

variable "digitalocean_spaces_key" {
  description = "DigitalOcean Spaces Secret Access Key"
  type        = string
  sensitive   = true
}
