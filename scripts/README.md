# Scripts Directory

Utility scripts for managing the K3s Kubernetes cluster and Proxmox infrastructure.

## 🔧 Infrastructure Scripts

### `create-ubuntu-template.sh`
Creates an Ubuntu Cloud-Init template VM for Proxmox cluster provisioning.

```bash
./create-ubuntu-template.sh [UBUNTU_VERSION] [TEMPLATE_ID] [STORAGE]
# Examples:
./create-ubuntu-template.sh                       # Uses 24.04 with defaults
./create-ubuntu-template.sh 22.04                 # Ubuntu 22.04 LTS
./create-ubuntu-template.sh 24.04 9001 nfs-shared # 24.04 on NFS storage
./create-ubuntu-template.sh 25.04 9002 ceph-pool  # 25.04 on Ceph storage
```

## 🔍 Diagnostic Scripts

### `validate-kubernetes.sh`
Validates all Kubernetes manifests in the `kubernetes/` directory using dry-run.

```bash
./validate-kubernetes.sh
```

**Checks:**
- YAML syntax validity
- Kubernetes API compatibility
- Reports valid/invalid file counts

## PostgreSQL Scripts

### `postgres-backup.sh`
Manual PostgreSQL backup script using pg_dumpall.

```bash
./postgres-backup.sh
```

**Features:**
- Lists available backup methods
- Triggers manual backup job
- Displays backup status and logs

### `postgres-restore.sh`
Restore PostgreSQL databases from pg_dumpall backups stored on a PVC (often NFS-backed).

```bash
# List available backups
./postgres-restore.sh --list

# Verify backup contents
./postgres-restore.sh postgres-backup-20260106-175055.sql.gz --verify

# Restore all databases
./postgres-restore.sh postgres-backup-20260106-175055.sql.gz

# Restore specific database only
./postgres-restore.sh postgres-backup-20260106-175055.sql.gz --database gatus
```

**Options:**
| Option | Description |
|--------|-------------|
| `--list` | List available backups on PVC |
| `--latest` | Use the most recent backup on PVC |
| `--verify` | Verify backup contents without restoring |
| `--database <name>` | Restore only a specific database |
| `--yes` | Skip confirmation prompt (DANGEROUS) |
| `--help` | Show usage information |

## 📋 Usage Notes

### Making Scripts Executable
```bash
chmod +x scripts/*.sh
```

### Running from Project Root
```bash
./scripts/postgres-restore.sh --list
```

### Environment Variables
Some scripts use environment variables:
- `PROXMOX_HOST` - Target Proxmox node IP
- `KUBECONFIG` - Path to kubeconfig file
- `POSTGRES_NAMESPACE` - PostgreSQL namespace (default: `postgres`)
- `POSTGRES_CLUSTER` - Cluster name (default: `postgres-cluster`)
