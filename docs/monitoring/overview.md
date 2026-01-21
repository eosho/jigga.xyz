# Monitoring Stack Overview

## Components

| Component | Purpose | Deployment |
|-----------|---------|------------|
| **Prometheus** | Metrics collection and storage | StatefulSet |
| **Alertmanager** | Alert routing and notifications | StatefulSet |
| **Grafana** | Visualization and dashboards | Deployment |
| **Loki** | Log aggregation | SingleBinary StatefulSet |
| **Alloy** | Log collection agent | DaemonSet |
| **kube-state-metrics** | Kubernetes object metrics | Deployment |
| **node-exporter** | Node-level metrics | DaemonSet |

## Data Flow

### Metrics

1. **ServiceMonitors** tell Prometheus which endpoints to scrape
2. **Prometheus** scrapes `/metrics` endpoints every 30s
3. **Alertmanager** receives alerts from Prometheus
4. **Grafana** queries Prometheus for dashboards

### Logs

1. **Alloy** collects logs from all pods via Kubernetes API
2. **Alloy** enriches logs with labels (namespace, pod, workflow, etc.)
3. **Loki** receives and stores logs
4. **Grafana** queries Loki via Explore

## Storage

| Component | Storage Class | Size | Retention |
|-----------|--------------|------|-----------|
| Prometheus | ceph-rbd | 10Gi | 7 days |
| Loki | ceph-rbd | 5Gi | 7 days |
| Grafana | ceph-rbd | 5Gi | N/A |

## Managed via Terraform

The monitoring stack is deployed via Terraform in `modules/monitoring/main.tf`:

- `helm_release.kube_prometheus_stack` - Prometheus, Alertmanager, Grafana
- `helm_release.loki` - Loki log aggregation
- `helm_release.alloy` - Log collection agent

## ServiceMonitors

ServiceMonitors are managed via Kustomize in `k8s/platform/monitoring/servicemonitors/`:

| ServiceMonitor | Target |
|----------------|--------|
| `argo-workflows-controller` | Argo Workflows controller metrics |
| `argo-workflows-server` | Argo Workflows server metrics |
| `argocd` | ArgoCD components (PodMonitor) |
| `ceph-csi-rbd-*` | Ceph CSI driver metrics |
| `cert-manager` | cert-manager metrics |
| `cloudflared` | Cloudflare tunnel metrics |
| `postgres-cluster` | PostgreSQL metrics (PodMonitor) |
| `unpoller` | UniFi network metrics |

## Alert Rules

Alert rules are managed in `k8s/platform/monitoring/alerts/`:

| File | Alerts |
|------|--------|
| `cluster-alerts.yaml` | Node CPU, memory, disk |
| `certificate-alerts.yaml` | TLS certificate expiry |
| `kubernetes-alerts.yaml` | Pod crashes, deployments |
| `target-down-alerts.yaml` | Monitoring targets down |
| `argocd-alerts.yaml` | GitOps sync status |
| `argo-workflows-alerts.yaml` | Workflow failures |
| `postgres-alerts.yaml` | Database health |
| `traefik-alerts.yaml` | Ingress errors |
| `vaultwarden-alerts.yaml` | Password manager health |
