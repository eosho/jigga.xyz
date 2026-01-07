# k8s/ - Kubernetes GitOps Structure

This directory follows the GitOps structure defined in [AGENTS.md](../AGENTS.md).

## Directory Layout

```
k8s/
├── bootstrap/            # GitOps bootstrap (ArgoCD root app)
├── clusters/             # Cluster-specific app selection
│   └── homelab/          # Our K3s cluster
│       └── apps/         # ArgoCD Application CRDs
├── apps/                 # Application definitions (cluster-agnostic)
│   ├── _template/        # Template for new apps
│   ├── homepage/
│   ├── mqtt/
│   ├── vault/
│   └── vaultwarden/
└── platform/             # Shared infrastructure configs
    ├── monitoring/
    └── metallb/
```

## Key Principles

1. **Git is the source of truth**
2. **Clusters select apps; apps never select clusters**
3. **Prefer plain Kubernetes YAML + Kustomize**
4. **Secrets must be encrypted** (SOPS + AGE)

## Adding a New Application

See [apps/_template/README.md](apps/_template/README.md) for instructions.

## Secrets Management

All secrets are encrypted with SOPS + AGE. See `.sops.yaml` in the repository root.

```bash
# Encrypt a secret
sops -e -i k8s/apps/<app>/config/secret.yaml

# Decrypt for viewing (do not commit decrypted!)
sops -d k8s/apps/<app>/config/secret.yaml
```

ArgoCD uses KSOPS to automatically decrypt secrets at reconcile time.
