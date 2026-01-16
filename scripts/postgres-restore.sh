#!/bin/bash
# PostgreSQL Restore Script for CloudNativePG
# Restores PostgreSQL databases from pg_dumpall backups stored on a PVC (NFS, etc.)
#
# Strategy:
# - Create a helper pod that mounts the backup PVC.
# - Stream the pg_dumpall file from helper pod -> into psql running inside CNPG primary.
# - Restore per-db sections only (skips global roles/db creation emitted by pg_dumpall).
# - Optionally restore one database via --database.
#
# Important:
# - This is destructive. It drops + recreates DB(s) before restore.
# - Roles/grants/global objects from pg_dumpall are intentionally skipped.
#
set -euo pipefail

# -----------------------------
# Configuration
# -----------------------------
NAMESPACE="${POSTGRES_NAMESPACE:-postgres}"
CLUSTER_NAME="${POSTGRES_CLUSTER:-postgres-cluster}"
BACKUP_PVC="${BACKUP_PVC:-postgres-backup}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

export KUBECONFIG

BACKUP_FILE=""

# Defaults / options
VERIFY_ONLY=false
USE_LATEST=false
ASSUME_YES=false
TARGET_DATABASE=""
KEEP_HELPER_POD=false
TIMEOUT_SECONDS=900
DRY_RUN=false

kc() {
  command kubectl --kubeconfig="$KUBECONFIG" "$@"
}

# -----------------------------
# Colors for output
# -----------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
  cat <<EOF
Usage: $0 [backup-file] [options]

Options:
  --list              List available backups on PVC
  --latest            Use the most recent backup on PVC
  --verify            Verify backup contents without restoring
  --database DB       Restore only a specific database
  --yes               Skip confirmation prompt (DANGEROUS)
  --keep-helper-pod   Do not delete helper pod (debugging)
  --timeout SEC       Wait timeout for restore streaming (default: ${TIMEOUT_SECONDS})
  --dry-run           Print actions but do not execute
  --help              Show help

Examples:
  $0 --list
  $0 --latest --verify
  $0 --latest --yes
  $0 postgres-backup-20260106-175055.sql.gz --database gatus --yes
EOF
  exit 1
}

# -----------------------------
# Small utilities
# -----------------------------
die() {
  log_error "$1"
  exit 1
}

cleanup_pod() {
  local pod_name="$1"
  if [ "$KEEP_HELPER_POD" = "true" ]; then
    log_warn "Keeping helper pod for debugging: ${pod_name}"
    return 0
  fi
  kc -n "$NAMESPACE" delete pod "$pod_name" --ignore-not-found=true >/dev/null 2>&1 || true
}

run_or_echo() {
  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

# -----------------------------
# Prereqs
# -----------------------------
check_prerequisites() {
  log_info "Checking prerequisites..."
  command -v kubectl >/dev/null 2>&1 || die "kubectl is not installed"

  kc get namespace "$NAMESPACE" >/dev/null 2>&1 || die "Namespace missing: $NAMESPACE"
  kc get pvc -n "$NAMESPACE" "$BACKUP_PVC" >/dev/null 2>&1 || die "PVC missing: $BACKUP_PVC (ns=$NAMESPACE)"

  log_info "Prerequisites check passed"
}

# -----------------------------
# PVC Pod helper
# -----------------------------
run_with_backup_pvc() {
  # Runs a command in a short-lived pod that mounts the backup PVC.
  # Prints command output to stdout.
  local cmd="$1"
  local pod_name="backup-util-$RANDOM"

  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] would run with pvc: ${cmd}"
    return 0
  fi

  kc -n "$NAMESPACE" apply -f - <<EOF >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
  namespace: ${NAMESPACE}
spec:
  restartPolicy: Never
  containers:
    - name: util
      image: busybox:1.36
      command: ["sh", "-c"]
      args:
        - |-
          set -eu
          ${cmd}
      volumeMounts:
        - name: backup
          mountPath: /backup
  volumes:
    - name: backup
      persistentVolumeClaim:
        claimName: ${BACKUP_PVC}
EOF

  kc -n "$NAMESPACE" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/${pod_name}" --timeout=120s >/dev/null 2>&1 || true
  kc -n "$NAMESPACE" logs "${pod_name}" 2>/dev/null || true
  kc -n "$NAMESPACE" delete pod "${pod_name}" --ignore-not-found=true >/dev/null 2>&1 || true
}

list_backups() {
  log_info "Available backups on PVC ($BACKUP_PVC):"
  echo ""
  run_with_backup_pvc 'ls -lh /backup/; echo; ls -t /backup/postgres-backup-*.sql.gz 2>/dev/null | head -n 50 || true'
  echo ""
}

pick_latest_backup() {
  local latest
  latest="$(run_with_backup_pvc 'ls -t /backup/postgres-backup-*.sql.gz 2>/dev/null | head -n 1 | sed "s|.*/||"')"
  latest="$(echo "$latest" | tail -n 1)"
  [ -n "$latest" ] || die "No backups found on PVC $BACKUP_PVC"
  echo "$latest"
}

check_backup_exists_on_pvc() {
  log_info "Checking backup exists on PVC: $BACKUP_FILE"
  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] would check /backup/${BACKUP_FILE}"
    return 0
  fi
  run_with_backup_pvc "test -f /backup/${BACKUP_FILE} && echo OK || echo MISSING" | tail -n 1 | grep -q OK \
    || die "Backup file not found on PVC: ${BACKUP_FILE}"
}

# -----------------------------
# Cluster helpers
# -----------------------------
find_primary_pod() {
  # Return the first primary pod name (if any).
  # We explicitly print each item then head -n 1 for stability.
  kc -n "$NAMESPACE" get pods \
    -l "cnpg.io/cluster=${CLUSTER_NAME},cnpg.io/instanceRole=primary" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    | head -n 1
}

wait_for_pod_ready() {
  local pod="$1"
  local timeout="${2:-120}"
  kc -n "$NAMESPACE" wait --for=condition=Ready "pod/${pod}" --timeout="${timeout}s" >/dev/null 2>&1 || true
}

reset_database_via_primary() {
  local primary_pod="$1"
  local db="$2"

  [ -n "$db" ] || die "reset_database_via_primary called with empty db"

  case "$db" in
    postgres|template0|template1)
      die "Refusing to reset protected database: $db"
      ;;
  esac

  log_info "Resetting database (drop+create): $db"
  run_or_echo kc -n "$NAMESPACE" exec "$primary_pod" -- /bin/bash -lc "\
    set -euo pipefail; \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c \"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${db}' AND pid <> pg_backend_pid();\" >/dev/null 2>&1 || true; \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c \"DROP DATABASE IF EXISTS \\\"${db}\\\";\"; \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c \"CREATE DATABASE \\\"${db}\\\";\"\
  "
}

ensure_app_permissions_all_schemas() {
  # Fix common restore fallout: objects owned by postgres, schema public not writable by app, etc.
  local primary_pod="$1"
  local db="$2"

  log_info "Fixing ownership/privileges for role app on $db (all non-system schemas)"

  # This block:
  # - makes app owner of db
  # - re-owners schemas except pg_*/information_schema
  # - grants usage/create on schemas
  # - grants privileges across tables/sequences/functions
  # - sets default privs for future objects
  run_or_echo kc -n "$NAMESPACE" exec "$primary_pod" -- /bin/bash -lc "\
    set -euo pipefail; \
    psql -U postgres -d postgres -v ON_ERROR_STOP=0 -c \"ALTER DATABASE \\\"${db}\\\" OWNER TO app;\" >/dev/null 2>&1 || true; \
    psql -U postgres -d \"${db}\" -v ON_ERROR_STOP=0 <<'SQL'
DO \$\$
DECLARE r RECORD;
BEGIN
  -- fix schema owners/grants
  FOR r IN
    SELECT nspname
    FROM pg_namespace
    WHERE nspname NOT LIKE 'pg_%'
      AND nspname <> 'information_schema'
  LOOP
    EXECUTE format('ALTER SCHEMA %I OWNER TO app', r.nspname);
    EXECUTE format('GRANT USAGE,CREATE ON SCHEMA %I TO app', r.nspname);
  END LOOP;

  -- broad grants (safe if empty)
  EXECUTE 'GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO app';
  EXECUTE 'GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO app';
  EXECUTE 'GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO app';

  -- default privs (future objects)
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO app';
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO app';
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO app';
END
\$\$;
SQL\
  " >/dev/null 2>&1 || true
}

# -----------------------------
# Verify
# -----------------------------
verify_backup() {
  local pod_name="backup-verify-$RANDOM"

  log_info "Verifying backup file: $BACKUP_FILE"

  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] would verify /backup/${BACKUP_FILE}"
    return 0
  fi

  kc -n "$NAMESPACE" apply -f - <<EOF >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
  namespace: ${NAMESPACE}
spec:
  restartPolicy: Never
  containers:
    - name: verify
      image: alpine:3.20
      command: ["/bin/sh", "-c"]
      args:
        - |-
          set -eu
          apk add --no-cache gzip >/dev/null 2>&1
          test -f "/backup/${BACKUP_FILE}" || { echo "Missing /backup/${BACKUP_FILE}"; ls -la /backup; exit 1; }
          echo "File size:"; ls -lh "/backup/${BACKUP_FILE}"
          echo ""
          echo "Backup head:"; gunzip -c "/backup/${BACKUP_FILE}" | head -50 || true
          echo ""
          echo "Databases:"; gunzip -c "/backup/${BACKUP_FILE}" | grep -E '^\\\\connect ' | head -50 || true
      volumeMounts:
        - name: backup
          mountPath: /backup
  volumes:
    - name: backup
      persistentVolumeClaim:
        claimName: ${BACKUP_PVC}
EOF

  kc -n "$NAMESPACE" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/${pod_name}" --timeout=120s >/dev/null 2>&1 || true
  kc -n "$NAMESPACE" logs "${pod_name}" 2>/dev/null || true
  kc -n "$NAMESPACE" delete pod "${pod_name}" --ignore-not-found=true >/dev/null 2>&1 || true
}

# -----------------------------
# Restore engine
# -----------------------------
create_helper_pod() {
  local helper_pod="$1"

  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] would create helper pod: ${helper_pod}"
    return 0
  fi

  kc -n "$NAMESPACE" apply -f - <<EOF >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${helper_pod}
  namespace: ${NAMESPACE}
spec:
  restartPolicy: Never
  containers:
    - name: stream
      image: alpine:3.20
      command: ["/bin/sh", "-c"]
      args:
        - |-
          set -eu
          apk add --no-cache gzip >/dev/null 2>&1
          sleep 36000
      volumeMounts:
        - name: backup
          mountPath: /backup
  volumes:
    - name: backup
      persistentVolumeClaim:
        claimName: ${BACKUP_PVC}
EOF

  wait_for_pod_ready "$helper_pod" 120
}

discover_dbs_in_dump() {
  local helper_pod="$1"

  if [ "$DRY_RUN" = "true" ]; then
    echo "[dry-run] would discover dbs from /backup/${BACKUP_FILE}"
    return 0
  fi

  kc -n "$NAMESPACE" exec "$helper_pod" -- /bin/sh -lc "\
    test -f /backup/${BACKUP_FILE} || exit 1; \
    gunzip -c /backup/${BACKUP_FILE} \
      | sed -n 's/^\\\\connect[[:space:]]\\+\\([^ ]\\+\\).*/\\1/p' \
      | grep -vE '^(template0|template1|postgres)$' \
      | sort -u\
  "
}

stream_db_section_into_primary() {
  local helper_pod="$1"
  local primary_pod="$2"
  local db="$3"

  # Stream only the section after "\connect <db>" until the next database section.
  #
  # pg_dumpall output can include per-database "CREATE DATABASE <nextdb>" lines *before*
  # the next "\connect" marker. If we only stop on "\connect", we can accidentally
  # leak DB-creation statements for the next DB into the current restore.
  #
  # We also run with ON_ERROR_STOP=1 so restore errors fail fast.
  set +e
  kc -n "$NAMESPACE" exec "$helper_pod" -- /bin/sh -lc \
    'DB="'"$db"'"; {
        printf "SET session_replication_role = replica;\n";
        gunzip -c "/backup/'"$BACKUP_FILE"'" \
          | awk -v db="$DB" '"'"'
            $1=="\\connect" {
              # \connect lines can be quoted (\connect "dbname"). Normalize.
              name=$2; gsub(/^\"|\"$/, "", name)
              if(in_db) exit
              if(name==db){ in_db=1; next }
            }
            in_db {
              # Stop before the next DB section header (pg_dumpall emits these between DBs).
              if($1=="CREATE" && $2=="DATABASE") exit
              if($1=="ALTER" && $2=="DATABASE") exit
              if($1=="COMMENT" && $2=="ON" && $3=="DATABASE") exit
              print
            }
          '"'"';
        printf "\nSET session_replication_role = origin;\n";
      }' \
    | kc -n "$NAMESPACE" exec -i "$primary_pod" -- /bin/bash -lc \
      "psql -U postgres -d \"${db}\" -v ON_ERROR_STOP=1"
  local rc=$?
  set -e
  return $rc
}

restore_via_primary_exec() {
  local target_db="${1:-}"

  local primary_pod
  primary_pod="$(find_primary_pod)"
  [ -n "$primary_pod" ] || die "Could not find CNPG primary pod for cluster: ${CLUSTER_NAME}"

  log_warn "Using restore via exec into CNPG primary: ${primary_pod}"
  log_warn "Restoring per-database sections only (skips global ROLE/DB DDL)."

  local helper_pod="backup-stream-$RANDOM"
  trap 'log_warn "Caught interrupt. Cleaning up..."; cleanup_pod "'"$helper_pod"'"; exit 1' INT TERM

  create_helper_pod "$helper_pod"

  # Validate backup exists inside helper pod
  if [ "$DRY_RUN" != "true" ]; then
    kc -n "$NAMESPACE" exec "$helper_pod" -- /bin/sh -lc "test -f /backup/${BACKUP_FILE}" \
      || { cleanup_pod "$helper_pod"; trap - INT TERM; die "Backup missing inside helper pod: ${BACKUP_FILE}"; }
  fi

  if [ -n "$target_db" ]; then
    echo "---"
    reset_database_via_primary "$primary_pod" "$target_db"

    log_info "Restoring database: ${target_db}"
    if stream_db_section_into_primary "$helper_pod" "$primary_pod" "$target_db"; then
      ensure_app_permissions_all_schemas "$primary_pod" "$target_db"
      cleanup_pod "$helper_pod"
      trap - INT TERM
      log_info "Restore completed for: ${target_db}"
      return 0
    else
      local rc=$?
      cleanup_pod "$helper_pod"
      trap - INT TERM
      die "Restore failed for ${target_db} (exit ${rc})"
    fi
  fi

  log_info "Discovering databases in dump..."
  local dbs
  dbs="$(discover_dbs_in_dump "$helper_pod")"
  [ -n "$dbs" ] || { cleanup_pod "$helper_pod"; trap - INT TERM; die "No databases found in dump"; }

  log_info "Databases to restore:"
  echo "$dbs" | sed 's/^/  - /'

  local last_rc=0
  while read -r db; do
    [ -n "$db" ] || continue
    echo "---"
    reset_database_via_primary "$primary_pod" "$db"

    log_info "Restoring database: ${db}"
    if stream_db_section_into_primary "$helper_pod" "$primary_pod" "$db"; then
      ensure_app_permissions_all_schemas "$primary_pod" "$db"
    else
      last_rc=$?
      log_warn "Restore exited non-zero for ${db} (exit ${last_rc}); continuing."
      ensure_app_permissions_all_schemas "$primary_pod" "$db"
    fi
  done <<< "$dbs"

  cleanup_pod "$helper_pod"
  trap - INT TERM

  if [ $last_rc -ne 0 ]; then
    die "Restore finished with errors (last exit ${last_rc})"
  fi

  log_info "In-pod restore completed"
}

# -----------------------------
# Restore wrapper + status
# -----------------------------
restore_backup() {
  log_warn "=========================================="
  log_warn "         RESTORE WARNING"
  log_warn "=========================================="
  echo ""

  if [ -n "$TARGET_DATABASE" ]; then
    log_warn "This will restore database: ${TARGET_DATABASE}"
  else
    log_warn "This will restore ALL databases in the dump"
  fi
  log_warn "Existing data will be OVERWRITTEN!"
  echo ""

  local confirm="no"
  if [ "$ASSUME_YES" = "true" ]; then
    confirm="yes"
  else
    read -r -p "Are you sure you want to proceed? (yes/no): " confirm
  fi

  if [ "$confirm" != "yes" ]; then
    log_info "Restore aborted"
    exit 0
  fi

  check_backup_exists_on_pvc
  log_info "Starting restore from: ${BACKUP_FILE}"

  restore_via_primary_exec "$TARGET_DATABASE"
}

show_cluster_status() {
  log_info "Cluster status:"
  kc get cluster.postgresql.cnpg.io -n "$NAMESPACE" "$CLUSTER_NAME" -o wide 2>/dev/null || true

  echo ""
  log_info "Pod status:"
  kc get pods -n "$NAMESPACE" -l cnpg.io/cluster="$CLUSTER_NAME" -o wide || true
}

# -----------------------------
# Main
# -----------------------------
main() {
  echo "=========================================="
  echo "PostgreSQL Restore Script (pg_dumpall)"
  echo "=========================================="
  echo ""

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage ;;
      --list)
        check_prerequisites
        list_backups
        exit 0
        ;;
      --latest) USE_LATEST=true; shift ;;
      --verify) VERIFY_ONLY=true; shift ;;
      --database)
        TARGET_DATABASE="${2:-}"
        [ -n "$TARGET_DATABASE" ] || die "--database requires a database name"
        shift 2
        ;;
      --yes) ASSUME_YES=true; shift ;;
      --keep-helper-pod) KEEP_HELPER_POD=true; shift ;;
      --timeout)
        TIMEOUT_SECONDS="${2:-}"
        [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || die "--timeout must be an integer"
        shift 2
        ;;
      --dry-run) DRY_RUN=true; shift ;;
      -*)
        die "Unknown option: $1"
        ;;
      *)
        BACKUP_FILE="$1"
        shift
        ;;
    esac
  done

  check_prerequisites

    if [ "$USE_LATEST" = "true" ]; then
    BACKUP_FILE="$(pick_latest_backup)"
    log_info "Selected latest backup: ${BACKUP_FILE}"
  fi

  # If user asked for --verify but did not specify a file, default to latest.
  if [ "$VERIFY_ONLY" = "true" ] && [ -z "$BACKUP_FILE" ] && [ "$USE_LATEST" != "true" ]; then
    BACKUP_FILE="$(pick_latest_backup)"
    log_info "No backup file provided; defaulting to latest for verify: ${BACKUP_FILE}"
  fi

  [ -n "$BACKUP_FILE" ] || { log_error "Backup file required (or use --latest)"; echo ""; list_backups; exit 1; }

  # verify
  verify_backup
  if [ "$VERIFY_ONLY" = "true" ]; then
    log_info "Verification complete"
    exit 0
  fi

  restore_backup
  echo ""

  show_cluster_status
  echo ""

  log_info "Restore completed!"
}

main "$@"
