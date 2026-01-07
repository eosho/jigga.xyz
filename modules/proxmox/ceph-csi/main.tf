# Proxmox Ceph CSI Module
# Provides persistent storage for Kubernetes using Proxmox's Ceph RBD

# Create namespace for Ceph CSI
resource "kubernetes_namespace_v1" "ceph_csi" {
  count = var.deploy_ceph_csi ? 1 : 0

  metadata {
    name = "ceph-csi"
    labels = {
      "app.kubernetes.io/name"       = "ceph-csi"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Deploy Ceph CSI RBD using Helm with inline configuration
resource "helm_release" "ceph_csi_rbd" {
  count = var.deploy_ceph_csi ? 1 : 0

  depends_on = [kubernetes_namespace_v1.ceph_csi]

  name       = "ceph-csi-rbd"
  repository = "https://ceph.github.io/csi-charts"
  chart      = "ceph-csi-rbd"
  namespace  = kubernetes_namespace_v1.ceph_csi[0].metadata[0].name
  version    = var.ceph_csi_version

  timeout       = 600
  wait          = true
  force_update  = true # Force update to fix stale releases
  recreate_pods = true # Recreate pods on upgrade to apply fixes

  values = [<<EOF
csiConfig:
  - clusterID: "${var.ceph_cluster_id}"
    monitors:
%{for mon in var.ceph_monitors~}
      - "${mon}"
%{endfor~}

secret:
  create: true
  name: csi-rbd-secret
  userID: "${var.ceph_user}"
  userKey: "${var.ceph_user_key}"

storageClass:
  create: true
  name: ceph-rbd
  clusterID: "${var.ceph_cluster_id}"
  pool: "${var.ceph_pool}"
  imageFeatures: "layering"
  reclaimPolicy: "${var.reclaim_policy}"
  volumeBindingMode: "Immediate"
  allowVolumeExpansion: true
  fstype: "${var.fs_type}"
  annotations:
    storageclass.kubernetes.io/is-default-class: "${var.set_default_storage_class}"

# Enable RBAC
serviceAccounts:
  nodeplugin:
    create: true
  provisioner:
    create: true

rbac:
  create: true

provisioner:
  replicaCount: 1

nodeplugin:
  tolerations:
    - operator: Exists
  # Use chart defaults for registrar image (automatically updated with chart version)

# Disable read affinity (empty value causes crashes)
readAffinity:
  enabled: false
EOF
  ]
}

# Add missing 'nodes' permission to provisioner ClusterRole
resource "kubernetes_cluster_role_binding_v1" "ceph_csi_provisioner_nodes" {
  count = var.deploy_ceph_csi ? 1 : 0

  depends_on = [helm_release.ceph_csi_rbd]

  metadata {
    name = "ceph-csi-rbd-provisioner-nodes"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "ceph-csi-rbd-provisioner-nodes"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "ceph-csi-rbd-provisioner"
    namespace = "ceph-csi"
  }
}

resource "kubernetes_cluster_role_v1" "ceph_csi_provisioner_nodes" {
  count = var.deploy_ceph_csi ? 1 : 0

  depends_on = [helm_release.ceph_csi_rbd]

  metadata {
    name = "ceph-csi-rbd-provisioner-nodes"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "ceph_csi_nodeplugin_nodes" {
  count = var.deploy_ceph_csi ? 1 : 0

  depends_on = [helm_release.ceph_csi_rbd]

  metadata {
    name = "ceph-csi-rbd-nodeplugin-nodes"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "ceph-csi-rbd-nodeplugin-nodes"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "ceph-csi-rbd-nodeplugin"
    namespace = "ceph-csi"
  }
}

resource "kubernetes_cluster_role_v1" "ceph_csi_nodeplugin_nodes" {
  count = var.deploy_ceph_csi ? 1 : 0

  depends_on = [helm_release.ceph_csi_rbd]

  metadata {
    name = "ceph-csi-rbd-nodeplugin-nodes"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "watch"]
  }
}

# Note: The null_resource patch was removed - chart v3.13.0+ handles args correctly
# The old patch was incorrectly targeting container index 1 which varied between deployments
