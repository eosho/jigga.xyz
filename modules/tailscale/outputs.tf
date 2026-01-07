# Tailscale Operator Module Outputs

output "namespace" {
  description = "Namespace where Tailscale Operator is deployed"
  value       = var.deploy_tailscale ? kubernetes_namespace_v1.tailscale[0].metadata[0].name : null
}

output "hostname" {
  description = "Tailscale hostname for this subnet router"
  value       = var.hostname
}

output "advertised_routes" {
  description = "Routes advertised to the Tailscale network"
  value       = var.advertised_routes
}

output "connector_name" {
  description = "Name of the Tailscale Connector resource"
  value       = var.deploy_tailscale ? var.hostname : null
}
