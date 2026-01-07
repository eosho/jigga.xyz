# Ceph CSI Module Outputs

output "namespace" {
  description = "Namespace where Ceph CSI is deployed"
  value       = var.deploy_ceph_csi ? kubernetes_namespace_v1.ceph_csi[0].metadata[0].name : null
}

output "storage_class_name" {
  description = "Name of the Ceph RBD storage class"
  value       = var.deploy_ceph_csi ? "ceph-rbd" : null
}

output "secret_name" {
  description = "Name of the Ceph CSI secret"
  value       = var.deploy_ceph_csi ? "csi-rbd-secret" : null
}

output "ceph_csi_ready" {
  description = "Indicates Ceph CSI is deployed and ready"
  value       = var.deploy_ceph_csi ? true : false

  depends_on = [
    helm_release.ceph_csi_rbd
  ]
}
