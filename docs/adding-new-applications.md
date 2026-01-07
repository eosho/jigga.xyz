# Adding New Applications

This guide explains how to add new applications to the GitOps-managed Kubernetes cluster using the standard Kustomize structure.

## Overview

Applications are managed via ArgoCD with an **App of Apps** pattern:

```
k8s/
├── apps/                          # Application definitions
│   ├── _template/                 # Copy this for new apps
│   ├── homepage/
│   ├── mqtt/
│   └── vaultwarden/
├── clusters/homelab/apps/         # ArgoCD Application CRDs
│   ├── root-app.yaml
│   ├── homepage.yaml
│   ├── mqtt.yaml
│   └── vaultwarden.yaml
└── platform/                      # Shared infrastructure
```

| Access Type | Domain Pattern | Use Case | Proxy |
|-------------|---------------|----------|-------|
| **Public** | `app.jigga.xyz` | Public-facing services | Cloudflare Tunnel |
| **Internal** | `app.int.jigga.xyz` | Admin tools, sensitive services | Tailscale VPN |

---

## Step 1: Create the Application Structure

Copy the template and customize:

```bash
cp -r k8s/apps/_template k8s/apps/myapp
```

This creates the standard structure:

```
k8s/apps/myapp/
├── namespace.yaml           # Namespace definition
├── config/
│   ├── configmap.yaml       # Non-sensitive configuration
│   └── secret.yaml          # Sensitive data (SOPS encrypted)
├── workload/
│   └── deployment.yaml      # Deployment/StatefulSet
├── networking/
│   ├── service.yaml         # ClusterIP service
│   └── ingressroute.yaml    # Traefik IngressRoute (optional)
└── kustomization.yaml       # Kustomize entrypoint
```

## Step 2: Define the Namespace

```yaml
# k8s/apps/myapp/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
  labels:
    app.kubernetes.io/name: myapp
```

## Step 3: Create the Workload

```yaml
# k8s/apps/myapp/workload/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myapp:latest
        ports:
        - containerPort: 8080
        envFrom:
        - configMapRef:
            name: myapp-config
        - secretRef:
            name: myapp-secret
```

## Step 4: Add Configuration

### ConfigMap (non-sensitive)

```yaml
# k8s/apps/myapp/config/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-config
  namespace: myapp
data:
  LOG_LEVEL: "info"
  APP_PORT: "8080"
```

### Secret (sensitive - must be encrypted)

Create the plaintext secret first:

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

**Encrypt before committing:**

```bash
sops --encrypt --in-place k8s/apps/myapp/config/secret.yaml
```

See [secrets-management.md](secrets-management.md) for full SOPS documentation.

## Step 5: Create the Service

```yaml
# k8s/apps/myapp/networking/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
  namespace: myapp
spec:
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
```

## Step 6: Update the Kustomization

```yaml
# k8s/apps/myapp/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: myapp

resources:
  - namespace.yaml
  - config/configmap.yaml
  - config/secret.yaml
  - workload/deployment.yaml
  - networking/service.yaml

labels:
  - pairs:
      app.kubernetes.io/name: myapp
      app.kubernetes.io/part-of: homelab
    includeSelectors: false
```

## Step 7: Create the ArgoCD Application

```yaml
# k8s/clusters/homelab/apps/myapp.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/yourusername/jigga.xyz.git
    targetRevision: main
    path: k8s/apps/myapp
  destination:
    server: https://kubernetes.default.svc
    namespace: myapp
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

## Step 8: Register with Root App

Add your app to the root application's kustomization:

```yaml
# k8s/clusters/homelab/apps/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - homepage.yaml
  - mqtt.yaml
  - vaultwarden.yaml
  - platform.yaml
  - reloader.yaml
  - myapp.yaml  # Add this line
```

## Step 9: Commit and Push

```bash
git add k8s/apps/myapp k8s/clusters/homelab/apps/myapp.yaml
git commit -m "feat(myapp): add new application"
git push
```

ArgoCD will automatically detect the new application and deploy it.

---

## Exposing Applications

### Option A: Public Access via Cloudflare Tunnel

Use this for services that need to be accessible from anywhere without VPN.

Edit `terraform.tfvars`:

```hcl
cloudflare_tunnel_ingress_rules = [
  { hostname = "jigga.xyz", service = "http://homepage.web:80" },
  { hostname = "passwords.jigga.xyz", service = "http://vaultwarden.vaultwarden:80" },
  # Add your new app:
  { hostname = "myapp.jigga.xyz", service = "http://myapp.myapp:80" }
]
```

Apply changes:

```bash
terraform apply
kubectl rollout restart deployment/cloudflared -n cloudflare
```

### Option B: Internal Access via Tailscale

Use this for admin tools, dashboards, and services that should only be accessible via VPN.

Add a Traefik IngressRoute to your app:

```yaml
# k8s/apps/myapp/networking/ingressroute.yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
  namespace: myapp
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`myapp.int.jigga.xyz`)
      kind: Rule
      services:
        - name: myapp
          port: 80
  tls:
    certResolver: letsencrypt-prod
```

Add to your `kustomization.yaml`:

```yaml
resources:
  - networking/ingressroute.yaml
```

Access via Tailscale:
1. Connect to Tailscale on your device
2. Navigate to `https://myapp.int.jigga.xyz`

> **Note**: The wildcard DNS `*.int.jigga.xyz` points to `192.168.7.230` (Traefik).
> Tailscale routes traffic via the `k3s-router` subnet router.

---

## DNS Configuration

### Public Domains (Cloudflare Tunnel)

DNS records are automatically created by Terraform when you add entries to `cloudflare_tunnel_ingress_rules`.

| Record | Type | Value | Proxied |
|--------|------|-------|---------|
| `myapp.jigga.xyz` | CNAME | `<tunnel-id>.cfargotunnel.com` | ✅ Yes |

### Internal Domains (Tailscale)

A wildcard record handles all `*.int.jigga.xyz` subdomains:

| Record | Type | Value | Proxied |
|--------|------|-------|---------|
| `*.int.jigga.xyz` | A | `192.168.7.230` | ❌ No |

This is managed in `main.tf`:

```hcl
resource "cloudflare_record" "internal_wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*.int"
  content = "192.168.7.230"  # Traefik LoadBalancer IP
  type    = "A"
  proxied = false
}
```

---

## Quick Reference

### Service URL Format

```
# Cloudflare Tunnel (public)
http://<service>.<namespace>:<port>

# Examples:
http://vaultwarden.vaultwarden:80
http://homepage.web:80
http://argocd-server.argocd:80
```

### Current Applications

| App | Public URL | Internal URL | Backend Service |
|-----|------------|--------------|-----------------|
| Homepage | `jigga.xyz` | - | `homepage.web:80` |
| Vaultwarden | `passwords.jigga.xyz` | - | `vaultwarden.vaultwarden:80` |
| MQTT | - | `mqtt.int.jigga.xyz` | `emqx.mqtt:18083` |
| ArgoCD | - | `argocd.int.jigga.xyz` | `argocd-server.argocd:443` |
| Grafana | - | `grafana.int.jigga.xyz` | `kube-prometheus-stack-grafana.monitoring:80` |
| Alertmanager | - | `alertmanager.int.jigga.xyz` | `kube-prometheus-stack-alertmanager.monitoring:9093` |

---

## Troubleshooting

### Public App Not Working

```bash
# 1. Check DNS resolves to tunnel
dig myapp.jigga.xyz +short
# Should return: <tunnel-id>.cfargotunnel.com

# 2. Check cloudflared pods are running
kubectl get pods -n cloudflare

# 3. Check cloudflared logs
kubectl logs -n cloudflare -l app=cloudflared --tail=50

# 4. Verify tunnel config includes your app
kubectl get configmap cloudflare-tunnel-config -n cloudflare -o yaml
```

### Internal App Not Working

```bash
# 1. Verify Tailscale is connected
tailscale status

# 2. Check subnet routes are advertised
# In Tailscale admin: Machines → k3s-router → should show routes

# 3. Test direct IP access
curl -k https://192.168.7.230 -H "Host: myapp.int.jigga.xyz"

# 4. Check Traefik has the route
kubectl get ingressroute -A | grep myapp

# 5. Check Traefik logs
kubectl logs -n kube-system -l app.kubernetes.io/name=traefik --tail=50
```

### Certificate Issues

For internal services using Let's Encrypt DNS-01 challenge:

```bash
# Check certificate status
kubectl get certificate -A

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Force certificate renewal
kubectl delete certificate myapp-tls -n myapp
```

---

## Best Practices

1. **Follow the standard structure** - Use `_template/` as your starting point
2. **Encrypt all secrets with SOPS** - Never commit plaintext secrets
3. **Use internal access by default** - Only expose publicly what needs to be public
4. **Enable TLS everywhere** - Even internal services should use HTTPS
5. **Use ArgoCD for deployments** - GitOps ensures consistency
6. **Monitor all services** - Add ServiceMonitor for Prometheus scraping
7. **Document your apps** - Update this guide when adding new services

## Related Documentation

- [Secrets Management](secrets-management.md) - SOPS + AGE encryption workflow
- [Architecture Overview](architecture-overview.md) - System design
- [Maintenance Guide](maintenance-guide.md) - Operational procedures
