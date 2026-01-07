# Scripts Directory

Utility scripts for managing the K3s Kubernetes cluster and Proxmox infrastructure.

## 🔧 Infrastructure Scripts

### `create-ubuntu-template.sh`
Creates an Ubuntu Cloud-Init template VM for Proxmox cluster provisioning.

```bash
./create-ubuntu-template.sh [TEMPLATE_ID] [STORAGE]
# Examples:
./create-ubuntu-template.sh                    # Uses defaults (9000, local-lvm)
./create-ubuntu-template.sh 9000 nfs-shared    # Shared NFS storage
./create-ubuntu-template.sh 9000 ceph-pool     # Ceph storage
```

### `add-metallb-route-to-existing-bridge.sh`
Adds MetalLB subnet (10.0.2.8/29) routing to existing Proxmox bridge (vmbr1).

```bash
PROXMOX_HOST=192.168.7.233 ./add-metallb-route-to-existing-bridge.sh
```

### `expand-metallb-ip-pool.sh`
Interactive script providing options to expand MetalLB IP pool configuration.

```bash
./expand-metallb-ip-pool.sh
```

## 🔥 Firewall Scripts

### `apply-traefik-firewall-rules.sh`
Applies iptables rules for MetalLB subnet traffic. Run on the gateway/firewall host.

```bash
./apply-traefik-firewall-rules.sh
```

### `manual-proxmox-firewall-commands.sh`
Outputs manual firewall commands to run on Proxmox hosts for MetalLB routing.

```bash
./manual-proxmox-firewall-commands.sh
```

### `configure-proxmox-metallb-subnet.sh` *(if exists)*
Configures Proxmox firewall and routing for MetalLB dedicated subnet.

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

### `monitor-metallb-routing.sh`
Monitors MetalLB routing status and logs connectivity tests.

```bash
./monitor-metallb-routing.sh
```

**Monitors:**
- MetalLB IP reachability (10.0.2.9)
- Subnet routing status
- Logs results to `/tmp/metallb-routing-monitor-*.log`

## � PostgreSQL Scripts

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
Restore PostgreSQL databases from pg_dumpall backups stored on NFS.

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
| `--list` | List available backups on NFS |
| `--verify` | Verify backup contents without restoring |
| `--database <name>` | Restore only a specific database |
| `--help` | Show usage information |

## 📋 Usage Notes

### Making Scripts Executable
```bash
chmod +x scripts/*.sh
```

### Running from Project Root
```bash
./scripts/validate-kubernetes.sh
./scripts/monitor-metallb-routing.sh
./scripts/postgres-restore.sh --list
```

### Environment Variables
Some scripts use environment variables:
- `PROXMOX_HOST` - Target Proxmox node IP
- `KUBECONFIG` - Path to kubeconfig file
- `POSTGRES_NAMESPACE` - PostgreSQL namespace (default: `postgres`)
- `POSTGRES_CLUSTER` - Cluster name (default: `postgres-cluster`)

## 🔐 Security Considerations

- Review scripts before execution, especially firewall modifications
- Backup iptables rules before applying changes: `iptables-save > ~/iptables-backup.rules`
- Test in non-production environment first
- Scripts modifying Proxmox require SSH access to nodes
- PostgreSQL restore scripts require cluster access via kubectl
