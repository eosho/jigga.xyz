# Homelab Cluster

This directory contains the ArgoCD Application definitions for the `homelab` K3s cluster.

## Cluster Details

| Property | Value |
|----------|-------|
| Name | homelab |
| Type | K3s |
| Nodes | ichigo (control), naruto, tanjiro |
| Location | Proxmox VMs |

## Application Selection

Per [AGENTS.md](../../../AGENTS.md): **"Clusters select apps; apps never select clusters."**

This directory contains ArgoCD Application CRDs that reference cluster-agnostic app definitions in `k8s/apps/`.

## Adding a New Application

1. Create the app in `k8s/apps/<app-name>/`
2. Create an ArgoCD Application CRD in `k8s/clusters/homelab/apps/<app-name>.yaml`
3. Add the reference to `kustomization.yaml`
4. Commit and push

ArgoCD's root-apps Application watches this directory and will auto-deploy.
