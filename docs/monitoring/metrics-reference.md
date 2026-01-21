# Metrics Reference

Common PromQL queries organized by service. Use these in Prometheus or Grafana.

## Cluster Health

### Node Status

```promql
# Nodes not ready
kube_node_status_condition{condition="Ready",status="false"}

# Node CPU usage %
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Node memory usage %
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100

# Node disk usage %
100 - ((node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100)

# Node network receive rate
rate(node_network_receive_bytes_total[5m])
```

### Pod Status

```promql
# Pods in bad state
kube_pod_status_phase{phase=~"Failed|Unknown|Pending"}

# Container restarts (last hour)
sum(increase(kube_pod_container_status_restarts_total[1h])) by (namespace, pod)

# OOMKilled containers
kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}

# Pods not ready
sum by (namespace, pod) (kube_pod_status_ready{condition="false"})
```

### Resource Usage

```promql
# CPU requests vs capacity
sum(kube_pod_container_resource_requests{resource="cpu"}) / sum(kube_node_status_allocatable{resource="cpu"})

# Memory requests vs capacity
sum(kube_pod_container_resource_requests{resource="memory"}) / sum(kube_node_status_allocatable{resource="memory"})

# Container CPU usage
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (namespace, pod)

# Container memory usage
sum(container_memory_working_set_bytes{container!=""}) by (namespace, pod)
```

## Argo Workflows

```promql
# Running workflows
argo_workflows_count{status="Running"}

# Failed workflows (last hour)
increase(argo_workflows_count{status="Failed"}[1h])

# Workflow duration (p99)
histogram_quantile(0.99, sum(rate(argo_workflows_workflow_duration_bucket[5m])) by (le))

# Pending pods
argo_workflows_pods_count{phase="Pending"}

# Controller queue depth
workqueue_depth{name=~".*workflow.*"}
```

## ArgoCD

```promql
# Sync status by app
argocd_app_info{sync_status!="Synced"}

# Health status by app
argocd_app_info{health_status!="Healthy"}

# Git fetch duration
histogram_quantile(0.99, sum(rate(argocd_git_request_duration_seconds_bucket[5m])) by (le))

# Repo server requests
rate(argocd_repo_server_requests_total[5m])

# App sync total
argocd_app_sync_total
```

## PostgreSQL (CNPG)

```promql
# Database up
cnpg_collector_up

# Active connections
cnpg_pg_stat_activity_count{state="active"}

# Connection utilization %
(cnpg_pg_stat_activity_count / cnpg_pg_settings_max_connections) * 100

# Transaction rate
rate(cnpg_pg_stat_database_xact_commit[5m])

# Replication lag (bytes)
cnpg_pg_replication_lag

# Database size
cnpg_pg_database_size_bytes

# Deadlocks
rate(cnpg_pg_stat_database_deadlocks[5m])

# Cache hit ratio
cnpg_pg_stat_database_blks_hit / (cnpg_pg_stat_database_blks_hit + cnpg_pg_stat_database_blks_read)
```

## Ceph CSI

```promql
# CSI operations total
csi_operations_total

# CSI operation duration
histogram_quantile(0.99, sum(rate(csi_operation_duration_seconds_bucket[5m])) by (le, method))

# Volume operations
csi_operations_total{method=~".*Volume.*"}

# Provisioner operations
rate(csi_operations_total{driver_name="rbd.csi.ceph.com"}[5m])
```

## cert-manager

```promql
# Certificate ready status
certmanager_certificate_ready_status{condition="True"}

# Certificates expiring soon (< 30 days)
certmanager_certificate_expiration_timestamp_seconds - time() < 30*24*60*60

# Certificate renewal errors
increase(certmanager_certificate_renewal_errors_total[1h])

# ACME client requests
rate(certmanager_http_acme_client_request_count[5m])
```

## Cloudflared

```promql
# Tunnel status
cloudflared_tunnel_active_streams

# Request rate
rate(cloudflared_tunnel_request_total[5m])

# Error rate
rate(cloudflared_tunnel_request_errors_total[5m])

# Response time (p99)
histogram_quantile(0.99, sum(rate(cloudflared_tunnel_response_time_bucket[5m])) by (le))
```

## Traefik / Ingress

```promql
# Request rate by entrypoint
sum(rate(traefik_entrypoint_requests_total[5m])) by (entrypoint)

# Error rate (5xx)
sum(rate(traefik_entrypoint_requests_total{code=~"5.."}[5m])) / sum(rate(traefik_entrypoint_requests_total[5m]))

# Request duration (p99)
histogram_quantile(0.99, sum(rate(traefik_entrypoint_request_duration_seconds_bucket[5m])) by (le))

# Open connections
traefik_entrypoint_open_connections

# TLS requests
sum(rate(traefik_entrypoint_requests_tls_total[5m])) by (entrypoint)
```

## Loki

```promql
# Ingestion rate (bytes/s)
rate(loki_distributor_bytes_received_total[5m])

# Log entries ingested
rate(loki_distributor_lines_received_total[5m])

# Query duration (p99)
histogram_quantile(0.99, sum(rate(loki_request_duration_seconds_bucket{route=~".*query.*"}[5m])) by (le))

# Chunk store operations
rate(loki_chunk_store_operations_total[5m])
```

## Alloy

```promql
# Targets discovered
alloy_target_scrape_pools_total

# Logs sent to Loki
rate(loki_write_sent_entries_total[5m])

# Dropped logs
rate(loki_write_dropped_entries_total[5m])

# Component health
alloy_component_controller_running_components
```

## UniFi Poller (if deployed)

```promql
# Client count
unpoller_client_total

# Client bandwidth (download)
rate(unpoller_client_receive_bytes_total[5m])

# Client bandwidth (upload)
rate(unpoller_client_transmit_bytes_total[5m])

# Access point clients
unpoller_device_clients{type="uap"}

# Switch port utilization
rate(unpoller_port_receive_bytes_total[5m])
```

## Alert Status

```promql
# All firing alerts
ALERTS{alertstate="firing"}

# Alerts by severity
count(ALERTS{alertstate="firing"}) by (severity)

# Specific alert
ALERTS{alertname="TargetDown"}
```

## Target Health

```promql
# All targets down
up == 0

# Targets by job
up{job=~".*"} == 0

# Scrape duration
scrape_duration_seconds
```
