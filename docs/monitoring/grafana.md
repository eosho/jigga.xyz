# Grafana Guide

Grafana provides dashboards and visualization for metrics and logs.

## Accessing Grafana

- **URL**: https://grafana.int.jigga.xyz
- **Internal**: http://kube-prometheus-stack-grafana.monitoring:80

### Default Credentials

Username: `admin`
Password: Set in `terraform.tfvars` as `grafana_admin_password`

## Data Sources

| Data Source | Type | URL |
|-------------|------|-----|
| Prometheus | prometheus | http://kube-prometheus-stack-prometheus.monitoring:9090 |
| Loki | loki | http://loki-gateway.monitoring.svc.cluster.local |

## Built-in Dashboards

The kube-prometheus-stack includes these dashboards:

### Kubernetes
- Kubernetes / Compute Resources / Cluster
- Kubernetes / Compute Resources / Namespace (Pods)
- Kubernetes / Compute Resources / Node
- Kubernetes / Compute Resources / Workload

### Infrastructure
- Node Exporter / Nodes
- CoreDNS
- etcd

## Using Explore

Explore is for ad-hoc queries without building dashboards.

1. Click **Explore** (compass icon)
2. Select data source (Prometheus or Loki)
3. Write your query
4. Click **Run query**

### Prometheus Queries in Explore

```promql
# CPU usage by node
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```

### Loki Queries in Explore

```logql
# All logs from namespace
{namespace="argo-workflows"}

# Filter errors
{namespace="argocd"} |= "error"
```

## Creating Dashboards

### From Scratch

1. Click **+** > **Dashboard**
2. Click **Add visualization**
3. Select data source
4. Write query
5. Configure visualization
6. Save dashboard

### Import from Grafana.com

1. Click **+** > **Import**
2. Enter dashboard ID or paste JSON
3. Select data sources
4. Click **Import**

#### Recommended Dashboards

| ID | Name | Use |
|----|------|-----|
| 1860 | Node Exporter Full | Detailed node metrics |
| 10419 | UniFi Poller Client DPI | Network traffic |
| 10414 | UniFi Poller Network Sites | UniFi overview |
| 13639 | Loki & Promtail | Log dashboard |

## Persisting Dashboards

Dashboards can be saved in two ways:

### 1. Via ConfigMap (GitOps)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"  # Required for auto-discovery
data:
  my-dashboard.json: |
    { ... dashboard JSON ... }
```

### 2. Via Helm Values

Add to `modules/monitoring/main.tf`:

```hcl
grafana:
  dashboards:
    default:
      my-dashboard:
        gnetId: 12345
        revision: 1
        datasource: Prometheus
```

## Variables

Dashboard variables make dashboards reusable:

### Query Variable

```promql
# Get all namespaces
label_values(kube_pod_info, namespace)

# Get pods in a namespace
label_values(kube_pod_info{namespace="$namespace"}, pod)
```

### Using Variables in Queries

```promql
sum(container_memory_usage_bytes{namespace="$namespace"}) by (pod)
```

## Annotations

Annotations mark events on graphs:

```promql
# Show deployments
ALERTS{alertname="Watchdog"}
```

## Alerting (Grafana Alerts)

Grafana can also create alerts, but we use Prometheus Alertmanager instead for consistency.

## Troubleshooting

### Dashboard Not Loading

1. Check Grafana logs:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=grafana
   ```
2. Verify data source connectivity in Settings > Data Sources

### Slow Queries

1. Reduce time range
2. Add more specific label filters
3. Use recording rules for complex queries

### Lost Dashboards

Dashboards stored in Grafana's database persist in the PVC. For GitOps, save dashboards as ConfigMaps.

## References

- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)
- [Grafana Dashboard Library](https://grafana.com/grafana/dashboards/)
- [Grafana Variables](https://grafana.com/docs/grafana/latest/dashboards/variables/)
