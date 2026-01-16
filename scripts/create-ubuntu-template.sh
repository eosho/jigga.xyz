#!/bin/bash
# =============================================================================
# Create Ubuntu Cloud-Init Template for Proxmox Cluster
# =============================================================================
# This script creates a template VM that can be shared across all Proxmox nodes
# when using shared storage (NFS, Ceph, ZFS, etc.)
#
# Usage: ./create-ubuntu-template.sh [UBUNTU_VERSION] [TEMPLATE_ID] [STORAGE]
#   UBUNTU_VERSION: Ubuntu version (22.04, 24.04, 25.04) - default: 24.04
#   TEMPLATE_ID:    VM ID for the template (default: auto-assigned based on version)
#   STORAGE:        Storage name (default: ceph-pool, use shared storage for cluster)
#
# Examples:
#   ./create-ubuntu-template.sh                       # Uses 24.04 with defaults
#   ./create-ubuntu-template.sh 22.04                 # Ubuntu 22.04 LTS
#   ./create-ubuntu-template.sh 24.04 9001 nfs-shared # 24.04 on NFS storage
#   ./create-ubuntu-template.sh 25.04 9002 ceph-pool  # 25.04 on Ceph storage
#
# Supported Ubuntu Versions:
#   22.04 LTS (Jammy Jellyfish) - Template ID default: 9000
#   24.04 LTS (Noble Numbat)    - Template ID default: 9001
#   25.04     (Plucky Puffin)   - Template ID default: 9002
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

get_ubuntu_codename() {
    local version="$1"
    case "$version" in
        22.04) echo "jammy" ;;
        24.04) echo "noble" ;;
        25.04) echo "plucky" ;;
        *)
            log_error "Unsupported Ubuntu version: $version"
            log_info "Supported versions: 22.04, 24.04, 25.04"
            exit 1
            ;;
    esac
}

get_default_template_id() {
    local version="$1"
    case "$version" in
        22.04) echo "9000" ;;
        24.04) echo "9001" ;;
        25.04) echo "9002" ;;
        *) echo "9000" ;;
    esac
}

get_version_short() {
    local version="$1"
    echo "${version//.}" # Remove dots: 22.04 -> 2204
}

# Parse arguments
UBUNTU_VERSION_INPUT="${1:-24.04}"
UBUNTU_CODENAME=$(get_ubuntu_codename "$UBUNTU_VERSION_INPUT")
DEFAULT_TEMPLATE_ID=$(get_default_template_id "$UBUNTU_VERSION_INPUT")
VERSION_SHORT=$(get_version_short "$UBUNTU_VERSION_INPUT")

TEMPLATE_ID="${2:-$DEFAULT_TEMPLATE_ID}"
STORAGE="${3:-ceph-pool}"
TEMPLATE_NAME="ubuntu-${VERSION_SHORT}-template"
IMAGE_URL="https://cloud-images.ubuntu.com/${UBUNTU_CODENAME}/current/${UBUNTU_CODENAME}-server-cloudimg-amd64.img"
WORK_DIR="/tmp/pve-template"


# Pre-flight checks
log_info "Starting Ubuntu cloud-init template creation..."
log_info "Ubuntu Version: ${UBUNTU_VERSION_INPUT} (${UBUNTU_CODENAME})"
log_info "Template ID: ${TEMPLATE_ID}"
log_info "Template Name: ${TEMPLATE_NAME}"
log_info "Storage: ${STORAGE}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

# Check if template already exists
if qm status ${TEMPLATE_ID} &>/dev/null; then
    log_error "VM ${TEMPLATE_ID} already exists!"
    log_info "To recreate, first destroy it: qm destroy ${TEMPLATE_ID}"
    exit 1
fi

# Check if storage exists
if ! pvesm status | grep -q "^${STORAGE}"; then
    log_error "Storage '${STORAGE}' not found!"
    log_info "Available storage:"
    pvesm status
    exit 1
fi

# Check storage type for cluster sharing info
STORAGE_TYPE=$(pvesm status | grep "^${STORAGE}" | awk '{print $2}')
if [[ "$STORAGE_TYPE" == "dir" ]] || [[ "$STORAGE_TYPE" == "lvm" ]] || [[ "$STORAGE_TYPE" == "lvmthin" ]]; then
    if [[ "$STORAGE" == "local"* ]]; then
        log_warn "Using local storage '${STORAGE}' - template will only be available on THIS node"
        log_warn "For cluster-wide access, use shared storage (NFS, Ceph, etc.)"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
fi


# Download Ubuntu cloud image
log_info "Creating work directory..."
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

IMAGE_FILE="${UBUNTU_CODENAME}-server-cloudimg-amd64.img"

if [[ -f "${IMAGE_FILE}" ]]; then
    log_info "Cloud image already exists, checking freshness..."
    # Re-download if older than 7 days
    if [[ $(find "${IMAGE_FILE}" -mtime +7 2>/dev/null) ]]; then
        log_info "Image is older than 7 days, re-downloading..."
        rm -f "${IMAGE_FILE}"
    else
        log_info "Using existing image (less than 7 days old)"
    fi
fi

if [[ ! -f "${IMAGE_FILE}" ]]; then
    log_info "Downloading Ubuntu ${UBUNTU_VERSION_INPUT} (${UBUNTU_CODENAME}) cloud image..."
    wget -q --show-progress "${IMAGE_URL}" -O "${IMAGE_FILE}"
fi


# Pre-configure the image using virt-customize
log_info "Checking for libguestfs-tools..."
if ! command -v virt-customize &>/dev/null; then
    log_warn "virt-customize not found. Installing libguestfs-tools..."
    apt-get update && apt-get install -y libguestfs-tools
fi

log_info "Customizing cloud image..."

# Use --firstboot-install instead of --install
# This installs packages on first boot when the VM has network access
# Much more reliable than installing during image customization
virt-customize -a "${IMAGE_FILE}" \
    --firstboot-command 'dpkg --configure -a' \
    --firstboot-command 'apt-get update' \
    --firstboot-command 'apt-get install -y qemu-guest-agent nfs-common neofetch htop curl' \
    --firstboot-command 'systemctl enable qemu-guest-agent' \
    --firstboot-command 'systemctl start qemu-guest-agent' \
    --run-command 'apt-get clean'

log_info "Image customization complete - packages will install on first boot"


# Create the VM
log_info "Creating VM ${TEMPLATE_ID}..."

qm create ${TEMPLATE_ID} \
    --name "${TEMPLATE_NAME}" \
    --description "Ubuntu ${UBUNTU_VERSION_INPUT} (${UBUNTU_CODENAME}) Cloud-Init Template - Created $(date +%Y-%m-%d)" \
    --ostype l26 \
    --machine q35 \
    --cpu host \
    --cores 2 \
    --sockets 1 \
    --memory 2048 \
    --scsihw virtio-scsi-single \
    --net0 virtio,bridge=vmbr0,firewall=0 \
    --net1 virtio,bridge=vmbr1,firewall=0 \
    --serial0 socket \
    --vga serial0 \
    --tags template,ubuntu,cloud-init,ubuntu-${VERSION_SHORT}


# Import the cloud image as the boot disk
log_info "Importing cloud image to storage '${STORAGE}'..."
qm set ${TEMPLATE_ID} --scsi0 ${STORAGE}:0,import-from="${WORK_DIR}/${IMAGE_FILE}",discard=on,ssd=1,iothread=1

# Add cloud-init drive
log_info "Adding cloud-init drive..."
qm set ${TEMPLATE_ID} --ide2 ${STORAGE}:cloudinit

# Configure boot and other settings
log_info "Configuring boot settings..."

# Set boot order (boot from SCSI disk)
qm set ${TEMPLATE_ID} --boot order=scsi0

# Enable QEMU guest agent
qm set ${TEMPLATE_ID} --agent enabled=1,fstrim_cloned_disks=1

# Set default cloud-init settings (these will be overridden by Terraform)
qm set ${TEMPLATE_ID} --ciuser groot
qm set ${TEMPLATE_ID} --citype nocloud

# Enable hotplug for disks and network
qm set ${TEMPLATE_ID} --hotplug disk,network,usb

# Convert to template
log_info "Converting VM to template..."
qm template ${TEMPLATE_ID}

# Cleanup
log_info "Cleaning up..."
# Keep the image for future use, only delete if explicitly requested
rm -f "${WORK_DIR}/${IMAGE_FILE}"

# Summary
echo ""
echo "============================================================================="
echo -e "${GREEN}Template created successfully!${NC}"
echo "============================================================================="
echo "Ubuntu Version: ${UBUNTU_VERSION_INPUT} (${UBUNTU_CODENAME})"
echo "Template ID:    ${TEMPLATE_ID}"
echo "Template Name:  ${TEMPLATE_NAME}"
echo "Storage:        ${STORAGE}"
echo ""

if [[ "$STORAGE_TYPE" == "nfs" ]] || [[ "$STORAGE_TYPE" == "ceph" ]] || [[ "$STORAGE_TYPE" == "rbd" ]] || [[ "$STORAGE_TYPE" == "zfspool" ]]; then
    echo -e "${GREEN} Using shared storage - template is available on ALL cluster nodes${NC}"
else
    echo -e "${YELLOW} Using local storage - template is only available on THIS node${NC}"
    echo "  To use on other nodes, either:"
    echo "  1. Run this script on each node with different template IDs"
    echo "  2. Migrate template to shared storage"
fi

echo ""
echo "To use in Terraform, set: vm_os_template = ${TEMPLATE_ID}"
echo ""
echo "To verify the template:"
echo "  qm config ${TEMPLATE_ID}"
echo ""
echo "To list templates on all nodes:"
echo "  pvesh get /cluster/resources --type vm | grep template"
echo ""
echo "To create all supported versions:"
echo "  ./create-ubuntu-template.sh 22.04"
echo "  ./create-ubuntu-template.sh 24.04"
echo "  ./create-ubuntu-template.sh 25.04"
echo "============================================================================="
