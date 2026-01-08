# Keycloak

Identity and Access Management (IAM) solution for SSO.

## Access

- **URL**: https://auth.int.jigga.xyz
- **Admin Console**: https://auth.int.jigga.xyz/admin
- **OAuth2 Proxy**: https://oauth.int.jigga.xyz

## Setup

### 1. Create Keycloak Database

Connect to PostgreSQL and create the database:

```sql
CREATE DATABASE keycloak;
CREATE USER keycloak WITH ENCRYPTED PASSWORD 'your-secure-password';
GRANT ALL PRIVILEGES ON DATABASE keycloak TO keycloak;
\c keycloak
GRANT ALL ON SCHEMA public TO keycloak;
```

### 2. Update Secrets

Edit `config/secret.yaml` with:
- Strong admin password
- Database credentials

### 3. Encrypt Secrets (SOPS)

```bash
sops -e -i k8s/apps/keycloak/config/secret.yaml
```

## Initial Configuration

After deployment:

1. Access admin console at https://auth.int.jigga.xyz/admin
2. Login with admin credentials
3. Create a realm called `homelab`
4. Configure identity providers (optional: GitHub, Google, etc.)

## OAuth2 Proxy Setup (ForwardAuth)

After Keycloak is running:

### 1. Create OAuth2 Proxy Client in Keycloak

1. Go to **Clients → Create Client**
2. **Client ID**: `oauth2-proxy`
3. **Client authentication**: ON
4. **Valid redirect URIs**: `https://oauth.int.jigga.xyz/oauth2/callback`
5. Go to **Credentials** tab and copy the client secret

### 2. Generate Cookie Secret

```bash
openssl rand -base64 32 | tr -- '+/' '-_'
```

### 3. Update OAuth2 Proxy Secret

Edit `config/oauth2-proxy-secret.yaml` with the client secret and cookie secret, then encrypt:

```bash
sops -e -i k8s/apps/keycloak/config/oauth2-proxy-secret.yaml
```

### 4. Add DNS Record

Add DNS for `oauth.int.jigga.xyz` → `192.168.7.230`

## Protecting Apps with ForwardAuth

To protect an app with Keycloak SSO, add this annotation to its Ingress:

```yaml
annotations:
  traefik.ingress.kubernetes.io/router.middlewares: keycloak-forward-auth@kubernetescrd
```

### Example: Protecting Headlamp

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: headlamp
  namespace: headlamp
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-dns-prod
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
    # Add this line to require Keycloak auth:
    traefik.ingress.kubernetes.io/router.middlewares: keycloak-forward-auth@kubernetescrd
```

## Apps Recommended for SSO Protection

| App | Recommendation |
|-----|----------------|
| Grafana | ✅ Has native OIDC support (better) |
| ArgoCD | ✅ Has native OIDC support (better) |
| Headlamp | ✅ Use ForwardAuth |
| Homepage | ✅ Use ForwardAuth |
| pgAdmin | ✅ Use ForwardAuth |
| Vaultwarden | ❌ Keep native auth (mobile apps) |
| Gatus | ❌ Usually public status page |

## Resources

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Traefik ForwardAuth](https://doc.traefik.io/traefik/middlewares/http/forwardauth/)
