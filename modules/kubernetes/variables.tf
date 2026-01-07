variable "deploy_kubernetes" {
  description = "Whether to deploy Kubernetes resources"
  type        = bool
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
}

variable "metallb_addresses" {
  description = "IP address ranges for MetalLB to use (list of CIDRs or /32s)"
  type        = list(string)
}