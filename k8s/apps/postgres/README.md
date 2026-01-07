# PostgreSQL (CloudNativePG)

High-availability PostgreSQL cluster managed by CloudNativePG operator.

## Architecture

```mermaid
flowchart TB
    subgraph cluster["PostgreSQL Cluster (postgres namespace)"]
        direction TB

        subgraph pods["Pods"]
            primary["🟢 postgres-cluster-1<br/>(Primary)"]
            replica1["🔵 postgres-cluster-2<br/>(Replica)"]
            replica2["🔵 postgres-cluster-3<br/>(Replica)"]
        end

        primary -->|"Streaming<br/>Replication"| replica1
        primary -->|"Streaming<br/>Replication"| replica2
    end

    subgraph services["Services"]
        rw["postgres-cluster-rw<br/>:5432"]
        ro["postgres-cluster-ro<br/>:5432"]
        r["postgres-cluster-r<br/>:5432"]
    end

    subgraph apps["Applications"]
        gatus["Gatus"]
        vaultwarden["Vaultwarden"]
        other["Other Apps"]
    end

    rw -->|"Read/Write"| primary
    ro -->|"Read Only<br/>(Load Balanced)"| replica1
    ro -->|"Read Only<br/>(Load Balanced)"| replica2
    r -->|"Any Instance"| pods

    apps -->|"DATABASE_URL"| rw

    subgraph backup["Backup (Daily 2AM UTC)"]
        cronjob["CronJob<br/>pg_dumpall"]
        nfs["NFS Storage<br/>192.168.1.246"]
    end

    cronjob -->|"Dump"| primary
    cronjob -->|"Store .sql.gz"| nfs
```

### Data Flow

```mermaid
sequenceDiagram
    participant App as Application
    participant RW as postgres-cluster-rw
    participant Primary as Primary (pod-1)
    participant Replica as Replicas (pod-2,3)

    App->>RW: Write Query
    RW->>Primary: Route to Primary
    Primary->>Primary: Execute & WAL
    Primary-->>Replica: Stream WAL
    Primary->>RW: Result
    RW->>App: Response

    App->>RW: Read Query
    RW->>Primary: Route to Primary
    Primary->>RW: Result
    RW->>App: Response

    Note over App,Replica: For read-heavy workloads, use postgres-cluster-ro
```

## Configuration

| Setting | Value |
|---------|-------|
| **PostgreSQL Version** | 18 |
| **Replicas** | 3 (1 primary + 2 replicas) |
| **Storage Class** | `ceph-rbd` |
| **Storage Size** | 10Gi per instance |
| **Namespace** | `postgres` |

## Databases

| Database | Used By | Description |
|----------|---------|-------------|
| `gatus` | Gatus | Status monitoring data |
| `vaultwarden` | Vaultwarden | Password manager data |
| `app` | Default | General purpose |

## Connection Strings

### For Applications (inside cluster)

```
# Read-Write (Primary)
postgresql://app:<password>@postgres-cluster-rw.postgres.svc.cluster.local:5432/<database>

# Read-Only (Replicas)
postgresql://app:<password>@postgres-cluster-ro.postgres.svc.cluster.local:5432/<database>
```

### Get Credentials

```bash
# App user password
kubectl get secret postgres-cluster-app -n postgres -o jsonpath='{.data.password}' | base64 -d

# Superuser password (for admin tasks only)
kubectl get secret postgres-superuser -n postgres -o jsonpath='{.data.password}' | base64 -d
```

## Backups

### Schedule

Daily at **2:00 AM UTC** via Kubernetes CronJob.

### Backup Method

- **Tool**: `pg_dumpall` (logical backup)
- **Format**: Gzipped SQL (`.sql.gz`)
- **Storage**: NFS (`192.168.1.246:/mnt/truenas-pool/pve/k8s/postgres`)
- **Retention**: Last 7 backups

### Manual Backup

```bash
# Trigger immediate backup
kubectl create job --from=cronjob/postgres-daily-backup postgres-backup-manual -n postgres

# Check backup status
kubectl get jobs -n postgres -l app.kubernetes.io/component=backup

# View backup logs
kubectl logs -n postgres -l job-name=postgres-backup-manual
```

### List Backups

```bash
./scripts/postgres-restore.sh --list
```

### Restore

```bash
# Verify backup contents
./scripts/postgres-restore.sh postgres-backup-YYYYMMDD-HHMMSS.sql.gz --verify

# Restore all databases
./scripts/postgres-restore.sh postgres-backup-YYYYMMDD-HHMMSS.sql.gz

# Restore specific database
./scripts/postgres-restore.sh postgres-backup-YYYYMMDD-HHMMSS.sql.gz --database gatus
```

## Monitoring

### pgAdmin

Web-based PostgreSQL administration at: **https://pgadmin.int.jigga.xyz**

```bash
# Get pgAdmin credentials
kubectl get secret pgadmin-secret -n pgadmin -o jsonpath='{.data.PGADMIN_DEFAULT_PASSWORD}' | base64 -d
```

### Prometheus Alerts

| Alert | Severity | Description |
|-------|----------|-------------|
| `PostgresClusterNotHealthy` | Critical | Cluster has unhealthy instances |
| `PostgresClusterNoLeader` | Critical | No primary instance |
| `PostgresReplicationLagHigh` | Warning | Replication lag > 30s |
| `PostgresConnectionsHigh` | Warning | Connections > 80% |
| `PostgresBackupJobFailed` | Critical | Backup CronJob failed |
| `PostgresBackupJobMissing` | Warning | No backup in 25 hours |

### Useful Commands

```bash
# Check cluster status
kubectl get cluster.postgresql.cnpg.io -n postgres

# Check pod status
kubectl get pods -n postgres -l cnpg.io/cluster=postgres-cluster

# View primary pod
kubectl get pods -n postgres -l cnpg.io/cluster=postgres-cluster,role=primary

# Connect to PostgreSQL
kubectl exec -it postgres-cluster-1 -n postgres -- psql -U postgres

# List databases
kubectl exec postgres-cluster-1 -n postgres -- psql -U postgres -c "SELECT datname FROM pg_database;"

# Check replication status
kubectl exec postgres-cluster-1 -n postgres -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

## Adding a New Database

1. Connect to primary:
   ```bash
   kubectl exec -it postgres-cluster-1 -n postgres -- psql -U postgres
   ```

2. Create database:
   ```sql
   CREATE DATABASE myapp;
   GRANT ALL PRIVILEGES ON DATABASE myapp TO app;
   ```

3. Update your application's secret with the connection string.

## Troubleshooting

### Cluster Not Healthy

```bash
# Check CloudNativePG operator logs
kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg

# Check cluster events
kubectl describe cluster.postgresql.cnpg.io postgres-cluster -n postgres
```

### Backup Failed

```bash
# Check CronJob status
kubectl get cronjob postgres-daily-backup -n postgres

# Check recent job logs
kubectl logs -n postgres -l app.kubernetes.io/component=backup --tail=50

# Verify NFS mount
kubectl exec -it postgres-cluster-1 -n postgres -- ls -la /backup/
```

### Connection Issues

```bash
# Test connectivity from within cluster
kubectl run -it --rm pg-test --image=postgres:18 --restart=Never -- \
  psql postgresql://app:<password>@postgres-cluster-rw.postgres.svc.cluster.local:5432/postgres -c "SELECT 1;"
```

## Files

```
k8s/apps/postgres/
├── config/
│   └── backup-volume.yaml    # NFS PV/PVC for backups
├── workload/
│   ├── cluster.yaml          # CloudNativePG Cluster resource
│   └── scheduled-backup.yaml # Backup CronJob
├── kustomization.yaml
├── namespace.yaml
├── secret-generator.yaml     # KSOPS generator for secrets
└── README.md
```
