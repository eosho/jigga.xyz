# Application Template

This is a template for creating new applications following the GitOps structure defined in [AGENTS.md](../../../AGENTS.md).

## Directory Structure

```
app-name/
├── namespace.yaml           # Namespace definition
├── config/
│   ├── configmap.yaml       # Non-sensitive configuration
│   └── secret.yaml          # SOPS-encrypted secrets
├── workload/
│   └── deployment.yaml      # Or statefulset.yaml
├── networking/
│   ├── service.yaml
│   └── ingress.yaml
├── kustomization.yaml       # Kustomize manifest
└── secret-generator.yaml    # KSOPS generator (if using secrets)
```

## Creating a New Application

1. Copy this template:
   ```bash
   cp -r k8s/apps/_template k8s/apps/my-new-app
   ```

2. Replace all occurrences of `APP_NAME` with your app name:
   ```bash
   find k8s/apps/my-new-app -type f -exec sed -i 's/APP_NAME/my-new-app/g' {} \;
   ```

3. Update the manifests with your actual configuration

4. Encrypt secrets with SOPS:
   ```bash
   sops -e -i k8s/apps/my-new-app/config/secret.yaml
   ```

5. Enable KSOPS in kustomization.yaml (uncomment generators section)

6. Test locally:
   ```bash
   kustomize build --enable-alpha-plugins --enable-exec k8s/apps/my-new-app
   ```

7. Create ArgoCD Application in `k8s/clusters/homelab/apps/`:
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: my-new-app
     namespace: argocd
   spec:
     project: default
     source:
       repoURL: git@github.com:eosho/jigga.xyz.git
       targetRevision: main
       path: k8s/apps/my-new-app
     destination:
       server: https://kubernetes.default.svc
       namespace: my-new-app
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
       syncOptions:
         - CreateNamespace=true
   ```

8. Commit and push - ArgoCD will deploy automatically!
