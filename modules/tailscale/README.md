# Tailscale Operator Module

Deploys the [Tailscale Kubernetes Operator](https://tailscale.com/kb/1236/kubernetes-operator) to connect your K8s cluster to your Tailscale network (tailnet).

## Features

- **Subnet Router**: Expose pod/service networks to your tailnet
- **Exit Node**: Optionally route all traffic through the cluster
- **OAuth Authentication**: Uses OAuth credentials (no expiry) instead of auth keys
- **Connector CRD**: Declarative subnet router configuration
- **ACL Tags**: Apply Tailscale ACL tags for access control

## Architecture

```
Tailscale Network (tailnet)
         ↓
  Tailscale Operator → Connector Pod
         ↓
  K8s Pod Network (10.42.0.0/16)
  K8s Service Network (10.43.0.0/16)
  LAN (192.168.7.0/24)
```

## Prerequisites

1. **Tailscale Account** at [login.tailscale.com](https://login.tailscale.com)

2. **Create OAuth Credentials**:
   - Go to [Admin Console → Settings → OAuth Clients](https://login.tailscale.com/admin/settings/oauth)
   - Create new OAuth client with scopes:
     - `devices:read`
     - `devices:write`
   - Save the Client ID and Client Secret

3. **Configure ACL Tags** (optional but recommended):
   ```json
   {
     "tagOwners": {
       "tag:k8s": ["autogroup:admin"]
     }
   }
   ```

## Usage

```hcl
module "tailscale" {
  source = "./modules/tailscale"

  kubeconfig_path = var.kubeconfig_path
  deploy_tailscale = true

  oauth_client_id     = var.tailscale_oauth_client_id
  oauth_client_secret = var.tailscale_oauth_client_secret

  hostname = "k3s-router"

  advertised_routes = [
    "10.42.0.0/16",      # Pod network
    "10.43.0.0/16",      # Service network
    "192.168.7.0/24"     # Home LAN (includes DNS 192.168.7.1, MetalLB 230-235, VMs)
  ]

  advertise_exit_node = false
  tags = ["tag:k8s"]
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `kubeconfig_path` | Path to the kubeconfig file | `string` | - | yes |
| `deploy_tailscale` | Whether to deploy the operator | `bool` | `false` | no |
| `oauth_client_id` | Tailscale OAuth Client ID | `string` | - | yes |
| `oauth_client_secret` | Tailscale OAuth Client Secret | `string` | - | yes |
| `hostname` | Hostname in your tailnet | `string` | `"k3s-router"` | no |
| `advertised_routes` | CIDRs to advertise | `list(string)` | See variables.tf | no |
| `advertise_exit_node` | Advertise as exit node | `bool` | `false` | no |
| `tags` | Tailscale ACL tags | `list(string)` | `["tag:k8s"]` | no |

## Outputs

| Name | Description |
|------|-------------|
| `namespace` | Namespace where operator is deployed |
| `hostname` | Tailscale hostname for the subnet router |
| `advertised_routes` | Routes advertised to tailnet |
| `connector_name` | Name of the Connector resource |

## Accessing Services

Once deployed, you can access K8s services from any device on your tailnet:

```bash
# Access a ClusterIP service
curl http://10.43.x.x:port

# Access a MetalLB LoadBalancer
curl http://192.168.7.230:port

# Access pods directly
curl http://10.42.x.x:port
```

## Approve Routes (First Time)

After deployment, approve the advertised routes in the Tailscale Admin Console:

1. Go to [Machines](https://login.tailscale.com/admin/machines)
2. Find `k3s-router` (or your configured hostname)
3. Click the machine → **Edit route settings**
4. Enable the advertised subnets

Or via CLI:
```bash
tailscale up --accept-routes
```

## Troubleshooting

```bash
# Check operator logs
kubectl logs -n tailscale -l app.kubernetes.io/name=operator

# Check connector status
kubectl get connectors -n tailscale
kubectl describe connector k3s-router -n tailscale

# Check connector pod
kubectl logs -n tailscale -l tailscale.com/parent-resource=k3s-router

# Verify routes are advertised
tailscale status
```

## Common Issues

### Routes Not Appearing
- Ensure OAuth client has correct scopes
- Check ACL allows the tags to advertise routes
- Verify routes are approved in Admin Console

### Connector Pod CrashLooping
```bash
kubectl logs -n tailscale -l tailscale.com/parent-resource=<hostname>
```
Usually indicates OAuth credential issues.

### Can't Reach Services
- Verify `--accept-routes` is enabled on client devices
- Check firewall rules on nodes allow tailscale traffic
- Ensure advertised CIDRs match actual network ranges

## Security Considerations

- OAuth credentials are stored as Kubernetes Secrets
- Use ACL tags to restrict which devices can access routes
- Consider separate tags for production vs development
- Store secrets in `terraform.tfvars` (gitignored) or Vault
