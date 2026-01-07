# Bootstrap

This directory contains GitOps bootstrap resources, primarily the ArgoCD root application configuration.

## Root Application

The root application implements the "App of Apps" pattern. It watches `k8s/clusters/homelab/apps/` and automatically creates ArgoCD Applications from the YAML files there.

**Note:** The root application itself is managed by Terraform (in `modules/argocd/`), but this directory serves as a reference and backup.

## Bootstrap Process

1. Terraform installs ArgoCD via Helm
2. Terraform creates the root-apps Application pointing to `k8s/clusters/homelab/apps/`
3. ArgoCD syncs and creates all child Applications
4. Each child Application syncs its respective app from `k8s/apps/<app>/`
