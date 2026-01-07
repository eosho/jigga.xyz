# Secrets Management with SOPS + AGE

This repository uses **SOPS (Secrets OPerationS)** with **AGE encryption** for managing Kubernetes secrets in a GitOps workflow. Secrets are encrypted at rest in Git and decrypted at deploy time by ArgoCD using KSOPS.

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Developer                                │
│  1. Create plaintext secret.yaml                                │
│  2. Run: sops --encrypt --in-place secret.yaml                  │
│  3. Commit encrypted secret to Git                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Git Repository                              │
│  Encrypted secrets stored safely                                │
│  Only metadata (keys, structure) visible                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ArgoCD + KSOPS                                │
│  1. ArgoCD syncs from Git                                       │
│  2. KSOPS plugin decrypts secrets using AGE private key         │
│  3. Decrypted secrets applied to cluster                        │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Local Development (WSL/Linux)

```bash
# Install SOPS
curl -LO https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
chmod +x sops-v3.11.0.linux.amd64
sudo mv sops-v3.11.0.linux.amd64 /usr/local/bin/sops

# Verify installation
sops --version
```

### AGE Key Setup

The AGE public key is stored in `.sops.yaml` at the repository root:

```yaml
creation_rules:
  - path_regex: .*secret.*\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age12r62ar5y9zapfu4xw8jmpavnzcwqfk52aywk9hft9pvs7lgu4c9s5dyngw
```

For decryption, you need the AGE private key:

```bash
# Set environment variable (add to ~/.bashrc or ~/.zshrc)
export SOPS_AGE_KEY_FILE=~/.sops/age-key.txt

# Or set the key directly
export SOPS_AGE_KEY="AGE-SECRET-KEY-..."
```

## Common Operations

### Encrypting a New Secret

1. **Create the plaintext secret:**

```yaml
# k8s/apps/myapp/config/secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: myapp-secret
  namespace: myapp
type: Opaque
stringData:
  DATABASE_PASSWORD: my-super-secret-password
  API_KEY: abc123xyz
```

2. **Encrypt the file:**

```bash
sops --encrypt --in-place k8s/apps/myapp/config/secret.yaml
```

3. **Verify encryption (values should be encrypted):**

```bash
cat k8s/apps/myapp/config/secret.yaml
```

4. **Commit to Git:**

```bash
git add k8s/apps/myapp/config/secret.yaml
git commit -m "feat(myapp): add encrypted secrets"
```

### Viewing an Encrypted Secret

```bash
# Decrypt and display (requires AGE private key)
sops --decrypt k8s/apps/myapp/config/secret.yaml

# Or use sops to open in viewer
sops k8s/apps/myapp/config/secret.yaml
```

### Editing an Encrypted Secret

```bash
# Opens decrypted content in $EDITOR, re-encrypts on save
sops k8s/apps/myapp/config/secret.yaml
```

### Rotating a Secret Value

1. Decrypt and edit:
   ```bash
   sops k8s/apps/myapp/config/secret.yaml
   ```

2. Change the value in your editor

3. Save and close - SOPS automatically re-encrypts

4. Commit the change:
   ```bash
   git add k8s/apps/myapp/config/secret.yaml
   git commit -m "chore(myapp): rotate database password"
   ```

## Secret File Structure

Encrypted secrets follow this pattern in the `k8s/apps/` structure:

```
k8s/apps/myapp/
├── config/
│   ├── configmap.yaml      # Non-sensitive config (plain YAML)
│   └── secret.yaml         # Sensitive data (SOPS encrypted)
├── workload/
│   └── deployment.yaml
├── networking/
│   └── service.yaml
└── kustomization.yaml
```

### Kustomization Integration

Reference SOPS-encrypted secrets as generators in your `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: myapp

resources:
  - namespace.yaml
  - workload/deployment.yaml
  - networking/service.yaml

generators:
  - config/secret-generator.yaml  # KSOPS generator

configMapGenerator:
  - name: myapp-config
    files:
      - config/configmap.yaml
```

With a KSOPS generator file:

```yaml
# config/secret-generator.yaml
apiVersion: viaduct.ai/v1
kind: ksops
metadata:
  name: myapp-secrets
files:
  - ./secret.yaml
```

## ArgoCD KSOPS Integration

ArgoCD is configured with KSOPS to decrypt secrets during sync. The configuration is in the ArgoCD Helm values:

```yaml
repoServer:
  env:
    - name: SOPS_AGE_KEY_FILE
      value: /app/config/age/key.txt
  volumes:
    - name: age-key
      secret:
        secretName: argocd-age-key
  volumeMounts:
    - name: age-key
      mountPath: /app/config/age
```

The AGE private key is stored as a Kubernetes secret in the `argocd` namespace (manually created, not in Git).

## Troubleshooting

### "could not decrypt data key"

**Cause:** Missing or incorrect AGE private key

**Solution:**
```bash
# Verify SOPS_AGE_KEY_FILE is set
echo $SOPS_AGE_KEY_FILE

# Verify the key file exists and has correct permissions
ls -la ~/.sops/age-key.txt

# The file should contain: AGE-SECRET-KEY-...
```

### "no matching keys found"

**Cause:** The secret was encrypted with a different AGE public key

**Solution:** Re-encrypt with the correct public key:
```bash
sops --decrypt --age "old-age-public-key" secret.yaml | \
sops --encrypt --age "age12r62ar5y9zapfu4xw8jmpavnzcwqfk52aywk9hft9pvs7lgu4c9s5dyngw" /dev/stdin > secret.yaml.new
mv secret.yaml.new secret.yaml
```

### ArgoCD shows "Sync Failed" for secrets

**Cause:** KSOPS plugin not configured or AGE key missing in ArgoCD

**Solution:**
1. Verify the `argocd-age-key` secret exists:
   ```bash
   kubectl get secret argocd-age-key -n argocd
   ```

2. Check ArgoCD repo-server logs:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/component=repo-server
   ```

## Security Best Practices

1. **Never commit plaintext secrets** - Always encrypt before committing
2. **Protect the AGE private key** - Store securely, never in Git
3. **Use `.gitignore` wisely** - Don't ignore `*secret*` patterns (blocks encrypted files)
4. **Audit secret access** - Review who has the AGE private key
5. **Rotate keys periodically** - Update AGE keys and re-encrypt all secrets
6. **Use namespaced secrets** - Each app's secrets in its own namespace

## Quick Reference

| Task | Command |
|------|---------|
| Encrypt new secret | `sops --encrypt --in-place secret.yaml` |
| View encrypted secret | `sops --decrypt secret.yaml` |
| Edit encrypted secret | `sops secret.yaml` |
| Encrypt specific fields | `sops --encrypt --encrypted-regex '^(data\|stringData)$' secret.yaml` |
| Check SOPS version | `sops --version` |
| Verify AGE key | `echo $SOPS_AGE_KEY_FILE` |

## Related Documentation

- [Adding New Applications](adding-new-applications.md) - How to add apps with secrets
- [Architecture Overview](architecture-overview.md) - Overall system design
- [SOPS Documentation](https://github.com/getsops/sops)
- [AGE Documentation](https://github.com/FiloSottile/age)
- [KSOPS Documentation](https://github.com/viaduct-ai/kustomize-sops)
