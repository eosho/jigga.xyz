resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.19.2"

  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "prometheus.enabled"
      value = "true"
    }
  ]
}

# Wait for the cert-manager webhook to be ready
resource "null_resource" "cert_manager_ready" {
  depends_on = [helm_release.cert_manager]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "export KUBECONFIG=${var.kubeconfig_path} && echo 'Waiting for cert-manager webhook to be ready...' && kubectl --insecure-skip-tls-verify -n cert-manager wait --for=condition=Available deployment/cert-manager-webhook --timeout=180s"
  }
}

locals {
  acme_server     = var.environment == "prod" ? "https://acme-v02.api.letsencrypt.org/directory" : "https://acme-staging-v02.api.letsencrypt.org/directory"
  issuer_name     = "letsencrypt-${var.environment}"
  dns_issuer_name = "letsencrypt-dns-${var.environment}"
}

# =============================================================================
# Cloudflare API Token Secret (for DNS-01 challenge)
# =============================================================================
# Creates secret directly via kubectl - no plaintext file written to disk
resource "null_resource" "apply_cloudflare_secret" {
  count      = var.enable_dns01 ? 1 : 0
  depends_on = [null_resource.cert_manager_ready]

  triggers = {
    api_token_hash = sha256(var.cloudflare_api_token)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      export KUBECONFIG=${var.kubeconfig_path}
      kubectl --insecure-skip-tls-verify -n cert-manager delete secret cloudflare-api-token --ignore-not-found
      kubectl --insecure-skip-tls-verify -n cert-manager create secret generic cloudflare-api-token \
        --from-literal=api-token='${var.cloudflare_api_token}'
    EOT
  }
}

# =============================================================================
# HTTP-01 ClusterIssuer (for public services)
# =============================================================================
resource "local_file" "cluster_issuer" {
  depends_on = [null_resource.cert_manager_ready]

  content = <<-EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${local.issuer_name}
spec:
  acme:
    email: ${var.email_address}
    server: ${local.acme_server}
    privateKeySecretRef:
      name: ${local.issuer_name}
    solvers:
      - http01:
          ingress:
            class: traefik
EOF

  filename = "${path.module}/cluster-issuer.yaml"
}

resource "null_resource" "apply_cluster_issuer" {
  depends_on = [local_file.cluster_issuer, null_resource.cert_manager_ready]

  triggers = {
    environment   = var.environment
    email_address = var.email_address
    issuer_name   = local.issuer_name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "export KUBECONFIG=${var.kubeconfig_path} && echo 'Applying HTTP-01 ClusterIssuer...' && sleep 5 && kubectl --insecure-skip-tls-verify apply -f ${path.module}/cluster-issuer.yaml"
  }
}

# =============================================================================
# DNS-01 ClusterIssuer (for internal services via Cloudflare)
# =============================================================================
resource "local_file" "dns_cluster_issuer" {
  count      = var.enable_dns01 ? 1 : 0
  depends_on = [null_resource.apply_cloudflare_secret]

  content = <<-EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${local.dns_issuer_name}
spec:
  acme:
    email: ${var.email_address}
    server: ${local.acme_server}
    privateKeySecretRef:
      name: ${local.dns_issuer_name}
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
        selector:
          dnsZones:
            - "${var.dns_zone}"
EOF

  filename = "${path.module}/cluster-issuer-dns01.yaml"
}

resource "null_resource" "apply_dns_cluster_issuer" {
  count      = var.enable_dns01 ? 1 : 0
  depends_on = [local_file.dns_cluster_issuer, null_resource.apply_cloudflare_secret]

  triggers = {
    environment   = var.environment
    email_address = var.email_address
    dns_zone      = var.dns_zone
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "export KUBECONFIG=${var.kubeconfig_path} && echo 'Applying DNS-01 ClusterIssuer...' && kubectl --insecure-skip-tls-verify apply -f ${path.module}/cluster-issuer-dns01.yaml"
  }
}