# Cloudflare Tunnel Module Outputs

output "namespace" {
  description = "Namespace where Cloudflare Tunnel is deployed"
  value       = var.deploy_cloudflare_tunnel ? kubernetes_namespace_v1.cloudflare[0].metadata[0].name : null
}

output "tunnel_name" {
  description = "Name of the Cloudflare Tunnel"
  value       = var.tunnel_name
}

output "metrics_service" {
  description = "Metrics service for Prometheus scraping"
  value       = var.deploy_cloudflare_tunnel ? "${kubernetes_service_v1.cloudflared_metrics[0].metadata[0].name}.${kubernetes_namespace_v1.cloudflare[0].metadata[0].name}.svc.cluster.local:2000" : null
}
