# Prometheus Guide

Prometheus collects and stores metrics from the Kubernetes cluster and applications.

## Accessing Prometheus

- **URL**: https://prometheus.int.jigga.xyz
- **Internal**: http://kube-prometheus-stack-prometheus.monitoring:9090

## PromQL Basics

PromQL is Prometheus's query language.

### Instant Vectors

```promql
# Current value of a metric
up

# Filter by label
up{job="kubernetes-nodes"}

# Regex match
up{job=~".*prometheus.*"}
```

### Range Vectors

```promql
# Values over the last 5 minutes
http_requests_total[5m]

# Rate of change per second
rate(http_requests_total[5m])

# Increase over time period
increase(http_requests_total[1h])
```

### Aggregations

```promql
# Sum across all instances
sum(up)

# Sum by label
sum(container_memory_usage_bytes) by (namespace)

# Average
avg(node_cpu_seconds_total) by (instance)

# Top 10
topk(10, sum(container_memory_usage_bytes) by (pod))
```

## Checking Targets

Navigate to **Status > Targets** to see all scrape targets:

| State | Meaning |
|-------|---------|
| **UP** | Target is healthy |
| **DOWN** | Target unreachable |
| **UNKNOWN** | First scrape pending |

## Adding Scrape Targets

### Via ServiceMonitor

Create a ServiceMonitor in `k8s/platform/monitoring/servicemonitors/`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: monitoring
  labels:
    release: kube-prometheus-stack  # Required!
spec:
  namespaceSelector:
    matchNames:
      - my-namespace
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

### Via PodMonitor (when no Service exists)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: my-app
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames:
      - my-namespace
  selector:
    matchLabels:
      app: my-app
  podMetricsEndpoints:
    - port: metrics
      interval: 30s
      path: /metrics
```

## Recording Rules

Recording rules pre-compute frequently used queries. They're defined in PrometheusRule CRDs:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-recording-rules
  namespace: monitoring
spec:
  groups:
    - name: my-app.rules
      rules:
        - record: my_app:request_rate:5m
          expr: sum(rate(http_requests_total[5m])) by (service)
```

## Common Operations

### Check Prometheus Health

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=100
```

### Force Reload Configuration

```bash
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -- kill -HUP 1
```

### Check TSDB Status

```bash
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -- \
  promtool tsdb analyze /prometheus
```

### Query via API

```bash
# Port forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Query
curl 'http://localhost:9090/api/v1/query?query=up'
```

## Troubleshooting

### Target Not Appearing

1. Check ServiceMonitor has `release: kube-prometheus-stack` label
2. Verify selector matches service labels:
   ```bash
   kubectl get svc -n <namespace> --show-labels
   ```
3. Check Prometheus operator logs:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator
   ```

### High Memory Usage

1. Check cardinality:
   ```promql
   topk(10, count by (__name__)({__name__=~".+"}))
   ```
2. Review retention settings
3. Add metric relabeling to drop high-cardinality labels

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)
- [Prometheus Operator](https://prometheus-operator.dev/)
