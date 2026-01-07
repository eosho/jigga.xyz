# Ceph CSI Module Variables

variable "deploy_ceph_csi" {
  description = "Whether to deploy Ceph CSI provisioner"
  type        = bool
  default     = true
}

variable "ceph_cluster_id" {
  description = "Ceph cluster FSID (run 'ceph fsid' on a Proxmox node)"
  type        = string
}

variable "ceph_monitors" {
  description = "List of Ceph monitor addresses (e.g., ['192.168.7.233:6789', '192.168.7.234:6789'])"
  type        = list(string)
}

variable "ceph_user" {
  description = "Ceph user for CSI (default: admin, recommended: create dedicated 'kubernetes' user)"
  type        = string
  default     = "admin"
}

variable "ceph_user_key" {
  description = "Ceph user keyring key (from 'ceph auth get-key client.<user>')"
  type        = string
  sensitive   = true
}

variable "ceph_pool" {
  description = "Ceph RBD pool name for Kubernetes volumes"
  type        = string
  default     = "kubernetes"
}

variable "ceph_csi_version" {
  description = "Ceph CSI Helm chart version"
  type        = string
  default     = "3.13.0" # Stable version with --enable-read-affinity fix
}

variable "set_default_storage_class" {
  description = "Set ceph-rbd as the default storage class"
  type        = bool
  default     = true
}

variable "reclaim_policy" {
  description = "Reclaim policy for the storage class (Delete or Retain)"
  type        = string
  default     = "Delete"

  validation {
    condition     = contains(["Delete", "Retain"], var.reclaim_policy)
    error_message = "Reclaim policy must be 'Delete' or 'Retain'."
  }
}

variable "fs_type" {
  description = "Filesystem type for RBD volumes"
  type        = string
  default     = "ext4"

  validation {
    condition     = contains(["ext4", "xfs"], var.fs_type)
    error_message = "Filesystem type must be 'ext4' or 'xfs'."
  }
}
