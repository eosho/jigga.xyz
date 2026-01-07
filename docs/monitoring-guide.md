# Monitoring Guide

This guide covers the Prometheus and Alertmanager setup for the K3s cluster.

## Overview

The monitoring stack consists of:
- **Prometheus** - Metrics collection and storage
- **Alertmanager** - Alert routing and notifications
- **Grafana** - Visualization dashboards

## Accessing Services

| Service | URL | Purpose |
|---------|-----|---------|
| Prometheus | https://prometheus.int.jigga.xyz | Query metrics, view targets |
| Alertmanager | https://alertmanager.int.jigga.xyz | View/silence alerts |
| Grafana | https://grafana.int.jigga.xyz | Dashboards and visualization |

## Prometheus

### Querying Metrics

Access the Prometheus UI and use PromQL to query metrics:

```promql
# CPU usage by node
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage percentage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Pod restarts in the last hour
increase(kube_pod_container_status_restarts_total[1h])

# HTTP request rate by service
sum(rate(traefik_entrypoint_requests_total[5m])) by (entrypoint)
```

### Checking Targets

Navigate to **Status > Targets** to see all scrape targets and their health status.

Common target states:
- **UP** - Target is healthy and being scraped
- **DOWN** - Target is unreachable
- **UNKNOWN** - Target state is not determined

### Service Discovery

Prometheus automatically discovers services via:
- ServiceMonitor CRDs
- PodMonitor CRDs
- Kubernetes service discovery

To add a new scrape target, create a ServiceMonitor:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 30s
```

## Alertmanager

### Viewing Active Alerts

1. Open https://alertmanager.int.jigga.xyz
2. Active alerts appear on the main page
3. Click an alert to see details and labels

### Silencing Alerts

To temporarily silence an alert:

1. Click **Silences** in the top nav
2. Click **New Silence**
3. Add matchers (e.g., `alertname=HighNodeCPU`)
4. Set duration and add a comment
5. Click **Create**

**Via CLI:**
```bash
# List active alerts
kubectl exec -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -- \
  amtool alert --alertmanager.url=http://localhost:9093

# Create a silence
kubectl exec -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -- \
  amtool silence add alertname=HighNodeCPU --duration=2h --comment="Maintenance window"
```

### Alert States

- **Firing** - Alert condition is active
- **Pending** - Condition met but waiting for `for` duration
- **Resolved** - Condition no longer met

## Alert Rules

### Location

Alert rules are defined in `k8s/platform/monitoring/alerts/`:

```
alerts/
├── kustomization.yaml
├── cluster-alerts.yaml      # Node CPU, memory, disk
├── certificate-alerts.yaml  # TLS cert expiry
├── kubernetes-alerts.yaml   # Pod crashes, deployments, PVCs
├── traefik-alerts.yaml      # Ingress health and errors
├── argocd-alerts.yaml       # GitOps sync status
└── vaultwarden-alerts.yaml  # Password manager health
```

### Adding New Alerts

1. Create or edit a `PrometheusRule` in the alerts directory:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-alerts
  namespace: monitoring
  labels:
    app.kubernetes.io/name: prometheus
    app.kubernetes.io/component: alerts
spec:
  groups:
    - name: my-app.rules
      rules:
        - alert: MyAppDown
          expr: up{job="my-app"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "My app is down"
            description: "My app has been unavailable for 5 minutes"
```

2. Add the file to `kustomization.yaml`:

```yaml
resources:
  - cluster-alerts.yaml
  - my-alerts.yaml  # Add here
```

3. Commit and push - ArgoCD will sync automatically

### Alert Severity Levels

| Severity | Description | Response Time |
|----------|-------------|---------------|
| `critical` | Service down, data loss risk | Immediate |
| `warning` | Degraded performance, approaching limits | Within hours |
| `info` | Informational, no action needed | Review when convenient |

## Grafana

### Default Dashboards

The kube-prometheus-stack includes pre-built dashboards:
- **Kubernetes / Compute Resources / Cluster**
- **Kubernetes / Compute Resources / Namespace (Pods)**
- **Node Exporter / Nodes**
- **CoreDNS**
- **etcd**

### Creating Custom Dashboards

1. Log into Grafana
2. Click **+** > **Dashboard**
3. Add panels with PromQL queries
4. Save the dashboard

**To persist dashboards in Git:**

1. Export dashboard JSON from Grafana UI
2. Save to `k8s/platform/monitoring/dashboards/`
3. Create a ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  my-dashboard.json: |
    { ... dashboard JSON ... }
```

## Common Operations

### Check Prometheus Health

```bash
# Pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus

# Logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=100

# TSDB status
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -- \
  promtool tsdb analyze /prometheus
```

### Check Alertmanager Health

```bash
# Pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=alertmanager

# Configuration status
kubectl exec -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -- \
  amtool check-config /etc/alertmanager/config/alertmanager.yaml
```

### View Firing Alerts via kubectl

```bash
# Get all PrometheusRules
kubectl get prometheusrules -n monitoring

# Describe a specific rule
kubectl describe prometheusrule basic-cluster-alerts -n monitoring

# Check alert status via Prometheus API
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Then visit http://localhost:9090/alerts
```

### Force Prometheus to Reload Rules

```bash
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -- \
  kill -HUP 1
```

## Troubleshooting

### Alert Not Firing

1. **Check the expression** - Test in Prometheus UI
2. **Verify labels match** - ServiceMonitor labels must match
3. **Check `for` duration** - Alert must be true for this period
4. **Verify PrometheusRule is loaded**:
   ```bash
   kubectl get prometheusrules -n monitoring
   ```

### Target Not Appearing

1. **Check ServiceMonitor exists**:
   ```bash
   kubectl get servicemonitors -n monitoring
   ```

2. **Verify label selector matches**:
   ```bash
   kubectl get svc -n <namespace> --show-labels
   ```

3. **Check Prometheus operator logs**:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator
   ```

### High Cardinality / Memory Issues

1. Check top metrics by cardinality:
   ```promql
   topk(10, count by (__name__)({__name__=~".+"}))
   ```

2. Review retention settings in Helm values

3. Consider adding metric relabeling to drop high-cardinality labels

## Useful PromQL Queries

### Cluster Health

```promql
# Nodes not ready
kube_node_status_condition{condition="Ready",status="false"}

# Pods in bad state
kube_pod_status_phase{phase=~"Failed|Unknown|Pending"}

# Container restarts (last hour)
sum(increase(kube_pod_container_status_restarts_total[1h])) by (namespace, pod)
```

### Resource Usage

```promql
# CPU requests vs limits
sum(kube_pod_container_resource_requests{resource="cpu"}) / sum(kube_node_status_allocatable{resource="cpu"})

# Memory by namespace
sum(container_memory_usage_bytes{namespace!=""}) by (namespace)

# PVC usage
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes
```

### Network

```promql
# Ingress request rate
sum(rate(traefik_entrypoint_requests_total[5m])) by (entrypoint)

# Error rate
sum(rate(traefik_entrypoint_requests_total{code=~"5.."}[5m])) / sum(rate(traefik_entrypoint_requests_total[5m]))
```

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)
- [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
