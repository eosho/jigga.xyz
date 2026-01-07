# =============================================================================
# ArgoCD Module Outputs
# =============================================================================

output "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed"
  value       = var.deploy_argocd ? "argocd" : ""
}

output "argocd_url" {
  description = "URL to access ArgoCD"
  value       = var.deploy_argocd ? "https://${var.argocd_domain}" : ""
}

output "argocd_server_service" {
  description = "ArgoCD server service name"
  value       = var.deploy_argocd ? "argocd-server" : ""
}

output "admin_password_command" {
  description = "Command to retrieve the initial ArgoCD admin password"
  value       = var.deploy_argocd ? "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d" : ""
}
