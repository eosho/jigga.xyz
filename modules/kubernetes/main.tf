# Kubernetes Infrastructure Module

# Deploy MetalLB using Helm
# Ref: https://metallb.universe.tf/installation/#installation-with-helm
resource "helm_release" "metallb" {
  count = var.deploy_kubernetes ? 1 : 0

  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = "0.15.3"
  namespace  = "metallb-system"

  create_namespace = true
  wait             = true
  timeout          = 900 # 15 minutes - allow for slow downloads
}

# MetalLB AddressPool for LoadBalancer Services
resource "local_file" "metallb_config" {
  count = var.deploy_kubernetes ? 1 : 0

  depends_on = [helm_release.metallb]

  content = <<-EOT
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lan-pool
  namespace: metallb-system
spec:
  addresses:
%{for cidr in var.metallb_addresses~}
  - ${cidr}
%{endfor~}
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lan-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - lan-pool
  interfaces:
  - eth0  # LAN interface
EOT

  filename = "${path.module}/metallb-config.yaml"
}

resource "null_resource" "apply_metallb_config" {
  count = var.deploy_kubernetes ? 1 : 0

  depends_on = [
    helm_release.metallb,
    local_file.metallb_config
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "kubectl --kubeconfig=${var.kubeconfig_path} --insecure-skip-tls-verify wait --for=condition=established --timeout=120s crd/ipaddresspools.metallb.io && kubectl --kubeconfig=${var.kubeconfig_path} --insecure-skip-tls-verify wait --for=condition=established --timeout=120s crd/l2advertisements.metallb.io && kubectl --kubeconfig=${var.kubeconfig_path} --insecure-skip-tls-verify apply -f ${path.module}/metallb-config.yaml"
  }
}