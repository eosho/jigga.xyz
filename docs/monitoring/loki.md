# Loki & Log Collection Guide

This guide covers log aggregation using Loki and Grafana Alloy.

## Overview

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Alloy     │───▶│    Loki     │◀───│   Grafana   │
│ (DaemonSet) │    │ (SingleBin) │    │  (Explore)  │
└─────────────┘    └─────────────┘    └─────────────┘
     │                   │
     ▼                   ▼
  Pod Logs          Ceph Storage
```

| Component | Role | Deployment |
|-----------|------|------------|
| **Alloy** | Collects logs from pods, adds labels | DaemonSet (1 per node) |
| **Loki** | Stores and indexes logs | SingleBinary with Ceph storage |
| **Grafana** | Query and visualize logs | Explore interface |

## Accessing Logs

### Via Grafana

1. Open https://grafana.int.jigga.xyz
2. Click **Explore** (compass icon) in the left sidebar
3. Select **Loki** as the data source
4. Use LogQL to query logs

### Via Argo Workflows UI

When viewing a workflow, click **WORKFLOW LOGS** to open Grafana with pre-filtered logs for that workflow.

## LogQL Query Language

LogQL is Loki's query language, similar to PromQL but for logs.

### Basic Queries

```logql
# All logs from a namespace
{namespace="argo-workflows"}

# Logs from a specific pod
{namespace="monitoring", pod="loki-0"}

# Logs from a specific container
{namespace="postgres", container="postgres"}

# Logs from an Argo workflow
{namespace="argo-workflows", workflow="my-workflow-abc123"}

# Logs from a specific node
{node_name="ichigo"}

# Logs from an app
{app="grafana"}
```

### Filtering Logs

```logql
# Filter by text (case-sensitive)
{namespace="argocd"} |= "error"

# Filter by text (case-insensitive)
{namespace="argocd"} |~ "(?i)error"

# Exclude lines
{namespace="monitoring"} != "health check"

# Regex match
{namespace="traefik"} |~ "status=(4|5)[0-9]{2}"

# Multiple filters (AND)
{namespace="argo-workflows"} |= "error" |= "workflow"
```

### Parsing Logs

```logql
# Parse JSON logs
{namespace="argo-workflows"} | json

# Access JSON fields after parsing
{namespace="argo-workflows"} | json | level="error"

# Parse with pattern (space-delimited)
{namespace="traefik"} | pattern `<ip> - - [<_>] "<method> <path> <_>" <status> <size>`

# Filter by parsed field
{namespace="traefik"} | pattern `<_> "<method> <path> <_>" <status> <_>` | status >= 400
```

### Metric Queries

Convert logs to metrics for dashboards:

```logql
# Count errors per namespace (over 5 minutes)
sum(count_over_time({namespace=~".+"} |~ "error" [5m])) by (namespace)

# Error rate per minute
sum(rate({namespace="argo-workflows"} |= "error" [1m])) by (pod)

# Bytes of logs per namespace
sum(bytes_over_time({namespace=~".+"}[1h])) by (namespace)

# Count of log lines per app
sum(count_over_time({app=~".+"}[5m])) by (app)
```

## Available Labels

Alloy automatically adds these labels to all logs:

| Label | Description | Example |
|-------|-------------|---------|
| `namespace` | Kubernetes namespace | `argo-workflows` |
| `pod` | Pod name | `my-workflow-abc-main` |
| `container` | Container name | `main` |
| `node_name` | Node where pod runs | `ichigo` |
| `app` | App label (if set) | `grafana` |
| `workflow` | Argo workflow name | `my-workflow-abc` |
| `workflow_template` | Argo workflow template | `ci-pipeline` |
| `argo_node_name` | Argo workflow node name | `main` |

### Listing Available Labels

In Grafana Explore, use the label browser or run:

```logql
# Show all unique values for a label
{namespace=~".+"} | __stream_shard__!=""
```

## Common Log Queries

### Argo Workflows

```logql
# All logs for a specific workflow
{namespace="argo-workflows", workflow="my-workflow-xyz"}

# Failed workflow steps
{namespace="argo-workflows"} |= "failed" | json | level="error"

# Workflow controller logs
{namespace="argo-workflows", pod=~"argo-workflows-workflow-controller.*"}
```

### ArgoCD

```logql
# Sync errors
{namespace="argocd"} |= "sync" |= "error"

# Application events
{namespace="argocd", pod=~"argocd-application-controller.*"}
```

### PostgreSQL

```logql
# Postgres errors
{namespace="postgres"} |= "ERROR"

# Slow queries (if log_min_duration_statement is set)
{namespace="postgres"} |= "duration:"

# Connection issues
{namespace="postgres"} |~ "connection|FATAL"
```

### Traefik / Ingress

```logql
# 5xx errors
{namespace="kube-system", pod=~"traefik.*"} |~ "\" 5[0-9]{2} "

# Specific path access
{namespace="kube-system", pod=~"traefik.*"} |= "/api/v1"
```

## Retention & Storage

- **Retention**: 7 days (configurable in `modules/monitoring/main.tf`)
- **Storage**: Ceph RBD (5Gi volume)
- **Schema**: TSDB with 24h index periods

To change retention, update `limits_config.retention_period` in the Loki Helm values.

## Alloy Configuration

Alloy is configured via Terraform in `modules/monitoring/main.tf`.

### Adding Custom Labels

To add labels from pod annotations or labels:

```hcl
# In the discovery.relabel "pods" block:
rule {
  source_labels = ["__meta_kubernetes_pod_label_MY_CUSTOM_LABEL"]
  target_label  = "my_custom_label"
}

# For annotations:
rule {
  source_labels = ["__meta_kubernetes_pod_annotation_MY_ANNOTATION"]
  target_label  = "my_annotation"
}
```

After editing, run `terraform apply`.

## Troubleshooting

### Logs Not Appearing

1. **Check Alloy is running**:
   ```bash
   kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy
   ```

2. **Check Alloy logs**:
   ```bash
   kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=50
   ```

3. **Verify Loki is healthy**:
   ```bash
   kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
   ```

4. **Test Loki API**:
   ```bash
   kubectl run curl-test --rm -it --restart=Never --image=curlimages/curl -- \
     curl -s "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/labels"
   ```

### Query Returns No Data

1. Check the time range in Grafana (default may be too short)
2. Verify the label values exist:
   ```logql
   {namespace="your-namespace"}
   ```
3. Check for typos in label names (labels are case-sensitive)

### High Memory Usage

If Loki uses too much memory:

1. Reduce retention period
2. Add more specific label selectors to reduce cardinality
3. Consider switching to distributed mode for larger deployments

## References

- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [LogQL Reference](https://grafana.com/docs/loki/latest/query/)
- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/)
- [Loki Best Practices](https://grafana.com/docs/loki/latest/best-practices/)
