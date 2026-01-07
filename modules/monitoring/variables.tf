variable "deploy_monitoring" {
  description = "Whether to deploy the monitoring stack"
  type        = bool
}

variable "monitoring_namespace" {
  description = "Namespace to deploy monitoring resources into"
  type        = string
  default     = "monitoring"
}

variable "grafana_admin_password" {
  description = "Password for the Grafana admin user"
  type        = string
  sensitive   = true
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
}

variable "grafana_domain" {
  description = "Domain name for Grafana ingress"
  type        = string
  default     = "grafana.local"
}

variable "k3s_server_ip" {
  description = "IP address of the K3s control plane node (for etcd metrics endpoint)"
  type        = string
}

variable "alertmanager_discord_webhook_url" {
  description = "Discord webhook URL for Alertmanager notifications"
  type        = string
  sensitive   = true
  default     = ""
}