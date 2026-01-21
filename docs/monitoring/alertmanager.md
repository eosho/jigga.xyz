# Alertmanager Guide

Alertmanager handles alert routing, grouping, silencing, and notifications.

## Accessing Alertmanager

- **URL**: https://alertmanager.int.jigga.xyz
- **Internal**: http://kube-prometheus-stack-alertmanager.monitoring:9093

## Viewing Alerts

1. Open Alertmanager UI
2. Active alerts appear on the main page
3. Click an alert to see labels and annotations

### Alert States

| State | Description |
|-------|-------------|
| **Firing** | Alert condition is active |
| **Pending** | Condition met, waiting for `for` duration |
| **Resolved** | Condition no longer met |

## Silencing Alerts

### Via UI

1. Click **Silences** in the top nav
2. Click **New Silence**
3. Add matchers (e.g., `alertname=HighNodeCPU`)
4. Set duration and comment
5. Click **Create**

### Via CLI

```bash
# List active alerts
kubectl exec -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -- \
  amtool alert --alertmanager.url=http://localhost:9093

# Create a silence (2 hours)
kubectl exec -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -- \
  amtool silence add alertname=HighNodeCPU \
    --duration=2h \
    --comment="Maintenance window" \
    --alertmanager.url=http://localhost:9093

# List silences
kubectl exec -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -- \
  amtool silence query --alertmanager.url=http://localhost:9093

# Expire a silence
kubectl exec -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0 -- \
  amtool silence expire <silence-id> --alertmanager.url=http://localhost:9093
```

## Alert Configuration

Alert routing is configured in `modules/monitoring/main.tf` under the `alertmanager.config` block.

### Current Routing

```yaml
route:
  group_by: ['alertname', 'namespace']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'discord'
  routes:
    - receiver: 'null'
      matchers:
        - alertname = "Watchdog"
    - receiver: 'null'
      matchers:
        - alertname = "InfoInhibitor"
```

### Receivers

| Receiver | Purpose |
|----------|---------|
| `discord` | Send alerts to Discord webhook |
| `null` | Discard alerts (used for Watchdog) |

## Adding Alert Rules

Alert rules are defined in `k8s/platform/monitoring/alerts/`.

### Create a PrometheusRule

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
            description: "{{ $labels.instance }} has been down for 5 minutes"
```

### Add to Kustomization

```yaml
# k8s/platform/monitoring/alerts/kustomization.yaml
resources:
  - my-alerts.yaml
```

## Alert Severity Levels

| Severity | Response | Examples |
|----------|----------|----------|
| `critical` | Immediate | Service down, data loss risk |
| `warning` | Hours | Degraded performance, approaching limits |
| `info` | Review later | Informational, no action needed |

## Inhibition Rules

Inhibit rules suppress alerts when related alerts are firing:

```yaml
inhibit_rules:
  - source_matchers:
      - severity = "critical"
    target_matchers:
      - severity = "warning"
    equal: ['alertname', 'namespace']
```

This prevents warning alerts when a critical alert for the same issue is already firing.

## Testing Alerts

### Check Alert Status in Prometheus

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/alerts
```

### Manually Fire a Test Alert

```bash
# Send a test alert to Alertmanager
curl -XPOST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {"alertname": "TestAlert", "severity": "warning"},
    "annotations": {"summary": "Test alert"}
  }]'
```

## Troubleshooting

### Alert Not Firing

1. Check expression in Prometheus UI
2. Verify `for` duration has elapsed
3. Check PrometheusRule is loaded:
   ```bash
   kubectl get prometheusrules -n monitoring
   ```

### Alert Not Reaching Discord

1. Check Alertmanager logs:
   ```bash
   kubectl logs -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0
   ```
2. Verify webhook URL is correct
3. Check routing matches the alert labels

## References

- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Alertmanager Configuration](https://prometheus.io/docs/alerting/latest/configuration/)
- [amtool](https://github.com/prometheus/alertmanager#amtool)
