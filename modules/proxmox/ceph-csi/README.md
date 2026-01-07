# Ceph CSI RBD Module

Deploys the Ceph CSI RBD provisioner for Kubernetes, enabling persistent volume claims backed by Proxmox's Ceph RBD storage.

## Prerequisites

Before using this module, set up Ceph on your Proxmox cluster:

### 1. Get Ceph Cluster ID (FSID)

SSH to any Proxmox node and run:

```bash
ceph fsid
```

### 2. Create a Ceph Pool for Kubernetes

```bash
# Create a new pool for Kubernetes (recommended)
ceph osd pool create kubernetes 64 64

# Set replication based on your cluster size
ceph osd pool set kubernetes size 2  # For 2-3 node clusters
# ceph osd pool set kubernetes size 3  # For 3+ node clusters

# Enable RBD application
ceph osd pool application enable kubernetes rbd

# Initialize the pool for RBD
rbd pool init kubernetes
```

### 3. Create a Ceph User for Kubernetes (Recommended)

```bash
# Create user with permissions for the kubernetes pool
ceph auth get-or-create client.kubernetes \
  mon 'profile rbd' \
  osd 'profile rbd pool=kubernetes' \
  mgr 'profile rbd pool=kubernetes'

# Get the key for terraform
ceph auth get-key client.kubernetes
```

Or use the admin key (simpler but less secure):
```bash
ceph auth get-key client.admin
```

## Usage

```hcl
module "ceph_csi" {
  source = "./modules/proxmox/ceph-csi"

  deploy_ceph_csi = true

  ceph_cluster_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"  # From 'ceph fsid'
  ceph_monitors   = ["192.168.7.233:6789", "192.168.7.234:6789", "192.168.7.235:6789"]
  ceph_user       = "kubernetes"  # or "admin"
  ceph_user_key   = "AQBxxxxxxxxxxxxxxxxxxxxxxxxxxxxx=="
  ceph_pool       = "kubernetes"

  providers = {
    kubernetes = kubernetes.kubernetes_provider
    helm       = helm.helm_provider
  }
}
```

## Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `deploy_ceph_csi` | Enable/disable Ceph CSI deployment | `bool` | `true` |
| `ceph_cluster_id` | Ceph cluster FSID | `string` | required |
| `ceph_monitors` | List of Ceph monitor addresses | `list(string)` | required |
| `ceph_user` | Ceph user for CSI | `string` | `"admin"` |
| `ceph_user_key` | Ceph user keyring key | `string` | required |
| `ceph_pool` | Ceph RBD pool name | `string` | `"kubernetes"` |
| `ceph_csi_version` | Helm chart version | `string` | `"3.10.0"` |
| `set_default_storage_class` | Set as default StorageClass | `bool` | `true` |
| `reclaim_policy` | PV reclaim policy | `string` | `"Delete"` |
| `fs_type` | Filesystem type (ext4/xfs) | `string` | `"ext4"` |

## Outputs

| Name | Description |
|------|-------------|
| `namespace` | Ceph CSI namespace |
| `storage_class_name` | Name of the StorageClass |
| `secret_name` | Name of the Ceph secret |
| `ceph_csi_ready` | Indicates CSI is ready |

## Testing

After deployment, test with a PVC:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-ceph-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ceph-rbd
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-ceph-pod
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: test-ceph-pvc
```

Verify:
```bash
kubectl get pvc test-ceph-pvc
kubectl get pv
kubectl exec test-ceph-pod -- df -h /data
```

## Troubleshooting

### Check Ceph CSI pods
```bash
kubectl -n ceph-csi get pods
kubectl -n ceph-csi logs -l app=ceph-csi-rbd
```

### Check StorageClass
```bash
kubectl get sc ceph-rbd -o yaml
```

### Verify Ceph connectivity from K3s nodes
```bash
# On a K3s node
apt install ceph-common
ceph --id kubernetes --keyring /tmp/keyring -m 192.168.7.233:6789 status
```
