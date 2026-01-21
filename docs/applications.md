# Applications & Endpoints

Quick reference for all deployed applications and their access endpoints.

---

## Web Applications (HTTPS)

| Application | URL | Description |
|-------------|-----|-------------|
| **Homepage** | https://home.int.jigga.xyz | Dashboard with links to all services |
| **Gatus** | https://uptime.int.jigga.xyz | Status page & uptime monitoring |
| **ArgoCD** | https://argocd.int.jigga.xyz | GitOps deployment platform |
| **Grafana** | https://grafana.int.jigga.xyz | Monitoring dashboards |
| **Prometheus** | https://prometheus.int.jigga.xyz | Metrics database & queries |
| **Alertmanager** | https://alertmanager.int.jigga.xyz | Alert management |
| **Vaultwarden** | https://passwords.int.jigga.xyz | Password manager (Bitwarden compatible) |
| **pgAdmin** | https://pgadmin.int.jigga.xyz | PostgreSQL administration |

---

## Non-HTTP Services

| Service | Endpoint | Protocol | Description |
|---------|----------|----------|-------------|
| **MQTT** | 192.168.7.231:1883 | TCP | MQTT broker (Mosquitto) |
| **Traefik** | 192.168.7.230:443 | HTTPS | Ingress controller |
| **PostgreSQL** | postgres-cluster-rw.postgres.svc:5432 | TCP | Database (cluster-internal) |

---

## Infrastructure VMs

| VM | IP Address | Port | Description |
|----|------------|------|-------------|
| **code-server** | 192.168.7.240 | 8080 | VS Code in browser |
| **PDM** | 192.168.7.241 | 8443 | Proxmox Datacenter Manager |

---

## Kubernetes Nodes

| Node | IP (SDN) | IP (K8s) | Role |
|------|----------|----------|------|
| ichigo | 10.0.0.10 | 192.168.7.223 | Control Plane |
| naruto | 10.0.0.11 | 192.168.7.224 | Worker |
| tanjiro | 10.0.0.12 | 192.168.7.225 | Worker |

---

## MetalLB IP Allocations

| IP | Service |
|----|---------|
| 192.168.7.230 | Traefik (Ingress) |
| 192.168.7.231 | Mosquitto (MQTT) |
| 192.168.7.232-235 | Available |

---

## Default Credentials

> ⚠️ **Change these in production!**

| Application | Username | Password/Token |
|-------------|----------|----------------|
| ArgoCD | admin | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" \| base64 -d` |
| Grafana | admin | (check secret or use SSO) |
| Gatus | - | No authentication (internal only) |
| pgAdmin | admin@jigga.xyz | `kubectl get secret pgadmin-secret -n pgadmin -o jsonpath="{.data.PGADMIN_DEFAULT_PASSWORD}" \| base64 -d` |
| PostgreSQL | app | `kubectl get secret postgres-cluster-app -n postgres -o jsonpath="{.data.password}" \| base64 -d` |

---

## Access Requirements

All `*.int.jigga.xyz` endpoints require one of:

1. **Tailscale VPN** - Connect via Tailscale to access internal services
2. **Direct Network Access** - Be on the 192.168.7.0/24 network
3. **Cloudflare Tunnel** - For public-facing services (if configured)

---

## Namespaces

| Namespace | Applications |
|-----------|--------------|
| `argocd` | ArgoCD |
| `cnpg-system` | CloudNativePG operator |
| `gatus` | Gatus status page |
| `monitoring` | Prometheus, Grafana, Alertmanager, node-exporter |
| `mqtt` | Mosquitto broker |
| `pgadmin` | pgAdmin PostgreSQL admin |
| `postgres` | PostgreSQL HA cluster (CloudNativePG) |
| `vaultwarden` | Vaultwarden password manager |
| `web` | Homepage |
| `argo-workflows` | Workflow automation (backups, cleanup tasks) |
| `kube-system` | Traefik, CoreDNS, MetalLB |
| `cert-manager` | Certificate management |

---

## Scheduled Tasks

Scheduled maintenance tasks (backups, cleanup jobs) run as Argo CronWorkflows.

- **UI**: https://workflows.int.jigga.xyz
- **Namespace**: `argo-workflows`

See [Maintenance Guide](maintenance-guide.md#scheduled-tasks-argo-workflows) for details on:
- PostgreSQL backup & restore procedures
- Cleanup job schedules
- Manual workflow execution