# =============================================================================
# ArgoCD Module Variables
# =============================================================================

variable "deploy_argocd" {
  description = "Whether to deploy ArgoCD"
  type        = bool
  default     = true
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "9.2.3"
}

variable "argocd_domain" {
  description = "Domain for ArgoCD UI"
  type        = string
  default     = "argocd.local"
}

variable "enable_notifications" {
  description = "Enable ArgoCD notifications controller"
  type        = bool
  default     = false
}

variable "admin_password_hash" {
  description = "Bcrypt hash of the admin password. Generate with: htpasswd -nbBC 10 '' 'password' | tr -d ':\\n'"
  type        = string
  default     = "" # Empty means use auto-generated password
}

variable "repositories_config" {
  description = "YAML config for repository credentials"
  type        = string
  default     = ""
}

# =============================================================================
# Root Application (App of Apps) Variables
# =============================================================================

variable "deploy_root_app" {
  description = "Whether to deploy the root application (app of apps pattern)"
  type        = bool
  default     = true
}

variable "git_repo_url" {
  description = "Git repository URL for ArgoCD applications"
  type        = string
  default     = "git@github.com:eosho/jigga.xyz.git"
}

variable "git_target_revision" {
  description = "Git branch/tag/commit to track"
  type        = string
  default     = "main"
}

variable "argocd_apps_path" {
  description = "Path in the repository to the ArgoCD applications folder"
  type        = string
  default     = "k8s/clusters/homelab/apps"
}

variable "git_ssh_private_key" {
  description = "SSH private key for Git repository access"
  type        = string
  default     = ""
  sensitive   = true
}

# =============================================================================
# SOPS/KSOPS Variables
# =============================================================================

variable "sops_age_key" {
  description = "AGE private key for SOPS secret decryption. Include the full key file contents."
  type        = string
  default     = ""
  sensitive   = true
}
