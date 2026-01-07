variable "grafana_domain" {
  description = "Domain name for Grafana"
  type        = string
  default     = "grafana.int.jigga.xyz"
}

variable "argocd_domain" {
  description = "Domain name for ArgoCD"
  type        = string
  default     = "argocd.int.jigga.xyz"
}

variable "deploy_argocd" {
  description = "Whether ArgoCD is deployed (to create its ingress)"
  type        = bool
  default     = false
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
}

variable "enable_tls" {
  description = "Whether to enable TLS for Ingress resources with Let's Encrypt"
  type        = bool
  default     = true
}

variable "cluster_issuer" {
  description = "Name of the ClusterIssuer for Let's Encrypt (DNS-01)"
  type        = string
  default     = "letsencrypt-dns-prod"
}