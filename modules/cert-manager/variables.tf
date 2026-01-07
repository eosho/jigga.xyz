variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
}

variable "email_address" {
  description = "Email address for Let's Encrypt notifications"
  type        = string
}

variable "environment" {
  description = "Which Let's Encrypt environment to use: 'prod' or 'staging'"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["prod", "staging"], var.environment)
    error_message = "Environment must be 'prod' or 'staging'."
  }
}

# DNS-01 Challenge Configuration (Cloudflare)
variable "enable_dns01" {
  description = "Enable DNS-01 challenge solver using Cloudflare"
  type        = bool
  default     = false
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit permissions"
  type        = string
  default     = ""
  sensitive   = true
}

variable "dns_zone" {
  description = "DNS zone for Cloudflare (e.g., jigga.xyz)"
  type        = string
  default     = ""
}