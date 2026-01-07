#!/bin/bash
# PostgreSQL Backup Script for CloudNativePG
# Creates an on-demand backup of the PostgreSQL cluster
#
# Usage: ./postgres-backup.sh [backup-name]
# Example: ./postgres-backup.sh manual-backup-2024-01-15

set -euo pipefail

# Configuration
NAMESPACE="${POSTGRES_NAMESPACE:-postgres}"
CLUSTER_NAME="${POSTGRES_CLUSTER:-postgres-cluster}"
BACKUP_NAME="${1:-manual-backup-$(date +%Y%m%d-%H%M%S)}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi

    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace $NAMESPACE does not exist"
        exit 1
    fi

    if ! kubectl get cluster.postgresql.cnpg.io -n "$NAMESPACE" "$CLUSTER_NAME" &> /dev/null; then
        log_error "Cluster $CLUSTER_NAME does not exist in namespace $NAMESPACE"
        exit 1
    fi

    log_info "Prerequisites check passed"
}

# Get cluster status
get_cluster_status() {
    log_info "Current cluster status:"
    kubectl get cluster.postgresql.cnpg.io -n "$NAMESPACE" "$CLUSTER_NAME" -o wide
    echo ""
    log_info "Pod status:"
    kubectl get pods -n "$NAMESPACE" -l cnpg.io/cluster="$CLUSTER_NAME" -o wide
}

# Create on-demand backup using pg_dump
create_backup() {
    log_info "Creating on-demand backup: $BACKUP_NAME"

    # Get the primary pod
    local primary_pod=$(kubectl get pods -n "$NAMESPACE" -l cnpg.io/cluster="$CLUSTER_NAME",role=primary -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$primary_pod" ]; then
        log_error "Could not find primary pod"
        exit 1
    fi

    log_info "Using primary pod: $primary_pod"

    # Create backup directory on NFS if it doesn't exist
    local backup_dir="/backup/${BACKUP_NAME}"

    # Run pg_dumpall to create a full backup
    log_info "Running pg_dumpall..."
    kubectl exec -n "$NAMESPACE" "$primary_pod" -c postgres -- \
        pg_dumpall -U postgres --clean --if-exists > "/tmp/${BACKUP_NAME}.sql"

    if [ $? -eq 0 ]; then
        log_info "Backup created successfully: /tmp/${BACKUP_NAME}.sql"
        local size=$(ls -lh "/tmp/${BACKUP_NAME}.sql" | awk '{print $5}')
        log_info "Backup size: $size"

        # Compress the backup
        log_info "Compressing backup..."
        gzip "/tmp/${BACKUP_NAME}.sql"
        local compressed_size=$(ls -lh "/tmp/${BACKUP_NAME}.sql.gz" | awk '{print $5}')
        log_info "Compressed size: $compressed_size"
        log_info "Backup file: /tmp/${BACKUP_NAME}.sql.gz"
    else
        log_error "pg_dumpall failed"
        exit 1
    fi

    log_info "Backup resource created. Backup completed!"
}

# Wait for backup to complete
wait_for_backup() {
    local timeout=600  # 10 minutes
    local interval=10
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        local phase=$(kubectl get backup -n "$NAMESPACE" "$BACKUP_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "unknown")

        case "$phase" in
            "completed")
                log_info "Backup completed successfully!"
                show_backup_details
                return 0
                ;;
            "failed")
                log_error "Backup failed!"
                kubectl get backup -n "$NAMESPACE" "$BACKUP_NAME" -o yaml
                return 1
                ;;
            "running"|"pending"|"unknown")
                log_info "Backup status: $phase (${elapsed}s elapsed)"
                sleep $interval
                elapsed=$((elapsed + interval))
                ;;
            *)
                log_warn "Unknown backup status: $phase"
                sleep $interval
                elapsed=$((elapsed + interval))
                ;;
        esac
    done

    log_error "Backup timed out after ${timeout}s"
    return 1
}

# Show backup details
show_backup_details() {
    log_info "Backup details:"
    kubectl get backup -n "$NAMESPACE" "$BACKUP_NAME" -o wide

    echo ""
    log_info "All backups:"
    kubectl get backup -n "$NAMESPACE" -l cnpg.io/cluster="$CLUSTER_NAME"
}

# List all backups
list_backups() {
    log_info "Available backups for cluster $CLUSTER_NAME:"
    kubectl get backup -n "$NAMESPACE" -l cnpg.io/cluster="$CLUSTER_NAME" -o wide

    echo ""
    log_info "Scheduled backups:"
    kubectl get scheduledbackup -n "$NAMESPACE" -o wide
}

# Main function
main() {
    echo "=========================================="
    echo "PostgreSQL Backup Script (CloudNativePG)"
    echo "=========================================="
    echo ""

    check_prerequisites
    get_cluster_status
    echo ""

    if [ "${1:-}" = "--list" ]; then
        list_backups
        exit 0
    fi

    create_backup

    echo ""
    log_info "Backup process completed"
}

# Run main
main "$@"
