#!/bin/bash
# PostgreSQL Restore Script for CloudNativePG
# Restores PostgreSQL databases from pg_dumpall backups on NFS
#
# Usage: ./postgres-restore.sh [backup-file]
# Example: ./postgres-restore.sh postgres-backup-20260106-175055.sql.gz
#
# If no backup file is specified, lists available backups.

set -euo pipefail

# Configuration
NAMESPACE="${POSTGRES_NAMESPACE:-postgres}"
CLUSTER_NAME="${POSTGRES_CLUSTER:-postgres-cluster}"
BACKUP_PVC="${BACKUP_PVC:-postgres-backup}"
BACKUP_FILE="${1:-}"
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

# Show usage
usage() {
    echo "Usage: $0 [backup-file] [options]"
    echo ""
    echo "Arguments:"
    echo "  backup-file    Name of the backup file to restore (e.g., postgres-backup-20260106-175055.sql.gz)"
    echo ""
    echo "Options:"
    echo "  --list         List available backups on NFS"
    echo "  --verify       Verify backup file contents without restoring"
    echo "  --database DB  Restore only a specific database (default: all)"
    echo "  --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --list"
    echo "  $0 postgres-backup-20260106-175055.sql.gz"
    echo "  $0 postgres-backup-20260106-175055.sql.gz --database gatus"
    echo "  $0 postgres-backup-20260106-175055.sql.gz --verify"
    exit 1
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

    if ! kubectl get pvc -n "$NAMESPACE" "$BACKUP_PVC" &> /dev/null; then
        log_error "Backup PVC $BACKUP_PVC does not exist in namespace $NAMESPACE"
        exit 1
    fi

    log_info "Prerequisites check passed"
}

# List available backups on NFS
list_backups() {
    log_info "Available backups on NFS ($BACKUP_PVC):"
    echo ""

    kubectl run -it --rm postgres-list-backups-$RANDOM \
        --namespace="$NAMESPACE" \
        --image=busybox \
        --restart=Never \
        --overrides="{
            \"spec\": {
                \"volumes\": [{
                    \"name\": \"backup\",
                    \"persistentVolumeClaim\": {\"claimName\": \"$BACKUP_PVC\"}
                }],
                \"containers\": [{
                    \"name\": \"list\",
                    \"image\": \"busybox\",
                    \"command\": [\"ls\", \"-lh\", \"/backup/\"],
                    \"volumeMounts\": [{
                        \"name\": \"backup\",
                        \"mountPath\": \"/backup\"
                    }]
                }]
            }
        }" 2>/dev/null || true

    echo ""
    log_info "To restore from a backup, run:"
    echo "  $0 <backup-filename>"
}

# Verify backup exists and show contents
verify_backup() {
    local verify_only="${1:-false}"

    log_info "Verifying backup file: $BACKUP_FILE"

    local pod_name="backup-verify-$RANDOM"

    # Create a pod to verify the backup
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  containers:
  - name: verify
    image: alpine
    command:
    - /bin/sh
    - -c
    - |
      apk add --no-cache gzip >/dev/null 2>&1
      if [ ! -f /backup/$BACKUP_FILE ]; then
        echo "ERROR: Backup file not found: $BACKUP_FILE"
        ls -la /backup/
        exit 1
      fi
      echo "File size:"
      ls -lh /backup/$BACKUP_FILE
      echo ""
      echo "Backup contents (first 50 lines):"
      gunzip -c /backup/$BACKUP_FILE | head -50
      echo ""
      echo "Databases in backup:"
      gunzip -c /backup/$BACKUP_FILE | grep "connect" | grep -v "connected" | head -20
    volumeMounts:
    - name: backup
      mountPath: /backup
  volumes:
  - name: backup
    persistentVolumeClaim:
      claimName: $BACKUP_PVC
EOF

    # Wait for pod to complete
    log_info "Waiting for verification to complete..."
    kubectl wait --for=condition=Ready pod/$pod_name -n "$NAMESPACE" --timeout=60s 2>/dev/null || true
    sleep 5

    # Get logs
    kubectl logs $pod_name -n "$NAMESPACE" 2>/dev/null || {
        log_error "Failed to get verification logs"
        kubectl delete pod $pod_name -n "$NAMESPACE" 2>/dev/null || true
        exit 1
    }

    # Cleanup
    kubectl delete pod $pod_name -n "$NAMESPACE" 2>/dev/null || true

    if [ "$verify_only" = "true" ]; then
        log_info "Verification complete"
        exit 0
    fi
}

# Restore from backup
restore_backup() {
    local target_database="${1:-}"

    log_warn "=========================================="
    log_warn "         RESTORE WARNING"
    log_warn "=========================================="
    echo ""

    if [ -n "$target_database" ]; then
        log_warn "This will restore database: $target_database"
        log_warn "Existing data in $target_database will be OVERWRITTEN!"
    else
        log_warn "This will restore ALL databases from backup!"
        log_warn "Existing data will be OVERWRITTEN!"
    fi

    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "Restore aborted"
        exit 0
    fi

    log_info "Starting restore from $BACKUP_FILE..."

    # Get app user password from secret
    local app_password=$(kubectl get secret -n "$NAMESPACE" "${CLUSTER_NAME}-app" -o jsonpath='{.data.password}' | base64 -d)

    if [ -z "$app_password" ]; then
        log_error "Failed to get app user password from secret ${CLUSTER_NAME}-app"
        exit 1
    fi

    local pod_name="backup-restore-$RANDOM"
    local restore_script=""

    if [ -n "$target_database" ]; then
        # Restore specific database
        restore_script="echo 'Restoring database: $target_database'; gunzip -c /backup/$BACKUP_FILE | sed -n '/connect $target_database/,/connect [^$target_database]/p' | head -n -1 | PGPASSWORD=\$PGPASSWORD psql -h ${CLUSTER_NAME}-rw -U app -d $target_database -v ON_ERROR_STOP=0"
    else
        # Full restore - all databases
        restore_script="echo 'Restoring all databases...'; gunzip -c /backup/$BACKUP_FILE | PGPASSWORD=\$PGPASSWORD psql -h ${CLUSTER_NAME}-rw -U app -d postgres -v ON_ERROR_STOP=0"
    fi

    # Create restore pod
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: $pod_name
  namespace: $NAMESPACE
spec:
  restartPolicy: Never
  containers:
  - name: restore
    image: postgres:18
    env:
    - name: PGPASSWORD
      value: "$app_password"
    command:
    - /bin/bash
    - -c
    - |
      $restore_script
    volumeMounts:
    - name: backup
      mountPath: /backup
  volumes:
  - name: backup
    persistentVolumeClaim:
      claimName: $BACKUP_PVC
EOF

    # Wait for pod to complete
    log_info "Waiting for restore to complete (this may take a while)..."
    kubectl wait --for=condition=Ready pod/$pod_name -n "$NAMESPACE" --timeout=60s 2>/dev/null || true

    # Follow logs until completion
    kubectl logs -f $pod_name -n "$NAMESPACE" 2>/dev/null || true

    # Wait for completion
    kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/$pod_name -n "$NAMESPACE" --timeout=300s 2>/dev/null || {
        log_warn "Restore may have encountered errors (check logs above)"
    }

    # Cleanup
    kubectl delete pod $pod_name -n "$NAMESPACE" 2>/dev/null || true

    log_info "Restore process completed"
}

# Show cluster status after restore
show_cluster_status() {
    log_info "Cluster status:"
    kubectl get cluster.postgresql.cnpg.io -n "$NAMESPACE" "$CLUSTER_NAME" -o wide 2>/dev/null || true

    echo ""
    log_info "Pod status:"
    kubectl get pods -n "$NAMESPACE" -l cnpg.io/cluster="$CLUSTER_NAME" -o wide

    echo ""
    log_info "Checking database connectivity..."
    local app_password=$(kubectl get secret -n "$NAMESPACE" "${CLUSTER_NAME}-app" -o jsonpath='{.data.password}' | base64 -d)

    local pod_name="db-check-$RANDOM"
    kubectl run $pod_name -n "$NAMESPACE" --image=postgres:18 --restart=Never --env="PGPASSWORD=$app_password" -- psql -h "${CLUSTER_NAME}-rw" -U app -d postgres -c "\l" 2>/dev/null
    sleep 5
    kubectl logs $pod_name -n "$NAMESPACE" 2>/dev/null || true
    kubectl delete pod $pod_name -n "$NAMESPACE" 2>/dev/null || true
}

# Main function
main() {
    echo "=========================================="
    echo "PostgreSQL Restore Script (pg_dumpall)"
    echo "=========================================="
    echo ""

    local verify_only=false
    local target_database=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                usage
                ;;
            --list)
                check_prerequisites
                list_backups
                exit 0
                ;;
            --verify)
                verify_only=true
                shift
                ;;
            --database)
                target_database="$2"
                shift 2
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                ;;
            *)
                BACKUP_FILE="$1"
                shift
                ;;
        esac
    done

    if [ -z "$BACKUP_FILE" ]; then
        log_error "Backup file is required"
        echo ""
        check_prerequisites
        list_backups
        exit 1
    fi

    check_prerequisites
    verify_backup "$verify_only"

    echo ""
    restore_backup "$target_database"

    echo ""
    show_cluster_status

    echo ""
    log_info "Restore completed!"
    log_info "Note: Some errors during restore are normal (e.g., 'role already exists')"
}

# Run main
main "$@"
