# Cloudflare Tunnel Module Variables

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
}

variable "deploy_cloudflare_tunnel" {
  description = "Whether to deploy Cloudflare Tunnel"
  type        = bool
  default     = false
}

variable "tunnel_name" {
  description = "Name of the Cloudflare Tunnel"
  type        = string
  default     = "jigga-tunnel"
}

variable "tunnel_credentials" {
  description = "Cloudflare Tunnel credentials JSON (from cloudflared tunnel create)"
  type = object({
    account_tag   = string
    tunnel_secret = string
    tunnel_id     = string
  })
  sensitive = true
}

variable "ingress_rules" {
  description = "List of ingress rules for the tunnel"
  type = list(object({
    hostname = string
    service  = string
  }))
  default = [
    {
      hostname = "jigga.xyz"
      service  = "http://homepage.svc.cluster.local:80"
    }
  ]
}

variable "replicas" {
  description = "Number of cloudflared replicas"
  type        = number
  default     = 2
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for DNS records"
  type        = string
  default     = ""
}

variable "create_dns_records" {
  description = "Whether to create CNAME DNS records for tunnel hostnames"
  type        = bool
  default     = true
}
