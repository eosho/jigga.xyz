output "metallb_namespace" {
  description = "Namespace where MetalLB is deployed"
  value       = "metallb-system"
}

output "ceph_csi_namespace" {
  description = "Namespace where Ceph CSI is deployed"
  value       = "ceph-csi"
}

output "default_storage_class" {
  description = "Name of the default storage class"
  value       = "ceph-rbd"
}