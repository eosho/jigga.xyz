# =============================================================================
# ArgoCD Module - GitOps Continuous Delivery
# =============================================================================

terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubectl = {
      source = "alekc/kubectl"
    }
  }
}

# =============================================================================
# ArgoCD Namespace (created before secrets and helm release)
# =============================================================================
resource "kubernetes_namespace_v1" "argocd" {
  count = var.deploy_argocd ? 1 : 0

  metadata {
    name = "argocd"
  }
}

# ArgoCD Helm Release
resource "helm_release" "argocd" {
  count = var.deploy_argocd ? 1 : 0

  depends_on = [kubernetes_namespace_v1.argocd, kubernetes_secret_v1.sops_age_key]

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = kubernetes_namespace_v1.argocd[0].metadata[0].name

  create_namespace = false # Namespace created separately to allow pre-creating secrets
  wait             = true
  timeout          = 600

  values = [<<EOF
# Global settings
global:
  domain: ${var.argocd_domain}

# Server configuration
server:
  # Ingress handled in ingress module
  ingress:
    enabled: false

  # Run insecure (TLS terminated at Traefik)
  extraArgs:
    - --insecure

  # Resource limits
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

# Repo server configuration
repoServer:
  # Environment variables for SOPS/KSOPS
  env:
    - name: XDG_CONFIG_HOME
      value: /.config
    - name: SOPS_AGE_KEY_FILE
      value: /.config/sops/age/keys.txt

  # Volume mounts for KSOPS and AGE key
  volumeMounts:
    - mountPath: /usr/local/bin/kustomize
      name: custom-tools
      subPath: kustomize
    - mountPath: /usr/local/bin/ksops
      name: custom-tools
      subPath: ksops
    - mountPath: /usr/local/bin/sops
      name: custom-tools
      subPath: sops
    - mountPath: /.config/sops/age
      name: sops-age

  # Volumes for custom tools and AGE key
  volumes:
    - name: custom-tools
      emptyDir: {}
    - name: sops-age
      secret:
        secretName: sops-age

  # Init container to install KSOPS, Kustomize, and SOPS using Alpine to download
  initContainers:
    - name: install-ksops
      image: alpine:3.19
      command: ["/bin/sh", "-c"]
      args:
        - |
          set -e
          echo "Downloading KSOPS and Kustomize..."
          wget -qO- https://github.com/viaduct-ai/kustomize-sops/releases/download/v4.3.2/ksops_4.3.2_Linux_x86_64.tar.gz | tar xz -C /custom-tools
          wget -qO- https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.3.0/kustomize_v5.3.0_linux_amd64.tar.gz | tar xz -C /custom-tools
          echo "Downloading SOPS..."
          wget -qO /custom-tools/sops https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
          chmod +x /custom-tools/ksops /custom-tools/kustomize /custom-tools/sops
          ls -la /custom-tools/
          echo "Done."
      volumeMounts:
        - mountPath: /custom-tools
          name: custom-tools

  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

# Application controller configuration
controller:
  resources:
    requests:
      cpu: 250m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi

# Redis configuration
redis:
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi

# Dex (SSO) - disabled by default
dex:
  enabled: false

# Notifications - disabled by default
notifications:
  enabled: ${var.enable_notifications}

# ApplicationSet controller
applicationSet:
  enabled: true
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi

# Config
configs:
  # Admin password (bcrypt hash)
  secret:
    argocdServerAdminPassword: "${var.admin_password_hash}"

  # Repository credentials (optional)
  repositories:
    ${indent(4, var.repositories_config)}

  # CM settings
  cm:
    # URL for ArgoCD
    url: https://${var.argocd_domain}

    # Enable status badge
    statusbadge.enabled: "true"

    # Application resync period (default 3 minutes)
    timeout.reconciliation: 180s

    # Exec enabled for debugging
    exec.enabled: "true"

    # Enable kustomize plugins for KSOPS
    kustomize.buildOptions: "--enable-alpha-plugins --enable-exec"
EOF
  ]
}

# Note: Ingress is defined in the ingress module for centralized management

# =============================================================================
# SOPS AGE Key Secret for KSOPS
# =============================================================================
# This secret contains the AGE private key used by KSOPS to decrypt secrets
# Must be created BEFORE helm_release.argocd since repo-server pods mount it
resource "kubernetes_secret_v1" "sops_age_key" {
  count = var.deploy_argocd && var.sops_age_key != "" ? 1 : 0

  depends_on = [kubernetes_namespace_v1.argocd]

  metadata {
    name      = "sops-age"
    namespace = "argocd"
  }

  data = {
    "keys.txt" = var.sops_age_key
  }
}

# =============================================================================
# SSH Repository Credentials Secret
# =============================================================================
# This secret allows ArgoCD to clone private Git repositories via SSH
resource "kubernetes_secret_v1" "repo_ssh_credentials" {
  count = var.deploy_argocd && var.git_ssh_private_key != "" ? 1 : 0

  depends_on = [helm_release.argocd]

  metadata {
    name      = "repo-ssh-credentials"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type          = "git"
    url           = var.git_repo_url
    sshPrivateKey = var.git_ssh_private_key
  }
}

# =============================================================================
# Root Application - App of Apps Pattern
# =============================================================================
# This deploys a single "root" Application that watches kubernetes/argocd-apps/
# and automatically creates all other ArgoCD Applications from YAML files.
resource "kubectl_manifest" "root_application" {
  count = var.deploy_argocd && var.deploy_root_app ? 1 : 0

  depends_on = [helm_release.argocd]

  force_conflicts = true

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root-apps"
      namespace = "argocd"
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.git_repo_url
        targetRevision = var.git_target_revision
        path           = var.argocd_apps_path
        directory = {
          recurse = false
          exclude = "{root-app.yaml,README.md}"
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune      = true
          selfHeal   = true
          allowEmpty = false
        }
        syncOptions = [
          "Validate=true",
          "PruneLast=true",
          "RespectIgnoreDifferences=true"
        ]
        retry = {
          limit = 5
          backoff = {
            duration    = "5s"
            factor      = 2
            maxDuration = "3m"
          }
        }
      }
    }
  })
}