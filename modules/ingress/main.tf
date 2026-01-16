resource "kubernetes_manifest" "grafana_ingress" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "grafana-ingress"
      namespace = "monitoring"
      annotations = var.enable_tls ? {
        "cert-manager.io/cluster-issuer"                   = var.cluster_issuer
        "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
        "traefik.ingress.kubernetes.io/router.tls"         = "true"
      } : {}
    }
    spec = {
      ingressClassName = "traefik"
      tls = var.enable_tls ? [
        {
          hosts      = [var.grafana_domain]
          secretName = "grafana-tls"
        }
      ] : null
      rules = [
        {
          host = var.grafana_domain
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "kube-prometheus-stack-grafana"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "prometheus_ingress" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "prometheus-ingress"
      namespace = "monitoring"
      annotations = var.enable_tls ? {
        "cert-manager.io/cluster-issuer"                   = var.cluster_issuer
        "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
        "traefik.ingress.kubernetes.io/router.tls"         = "true"
      } : {}
    }
    spec = {
      ingressClassName = "traefik"
      tls = var.enable_tls ? [
        {
          hosts      = [var.prometheus_domain]
          secretName = "prometheus-tls"
        }
      ] : null
      rules = [
        {
          host = var.prometheus_domain
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "kube-prometheus-stack-prometheus"
                    port = {
                      number = 9090
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "alertmanager_ingress" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "alertmanager-ingress"
      namespace = "monitoring"
      annotations = var.enable_tls ? {
        "cert-manager.io/cluster-issuer"                   = var.cluster_issuer
        "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
        "traefik.ingress.kubernetes.io/router.tls"         = "true"
      } : {}
    }
    spec = {
      ingressClassName = "traefik"
      tls = var.enable_tls ? [
        {
          hosts      = [var.alertmanager_domain]
          secretName = "alertmanager-tls"
        }
      ] : null
      rules = [
        {
          host = var.alertmanager_domain
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "kube-prometheus-stack-alertmanager"
                    port = {
                      number = 9093
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }
}


# ArgoCD Ingress - exposes ArgoCD via Traefik
resource "kubernetes_manifest" "argocd_ingress" {
  count = var.deploy_argocd ? 1 : 0

  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "argocd-ingress"
      namespace = "argocd"
      annotations = merge(
        {
          "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
          "traefik.ingress.kubernetes.io/router.tls"         = "true"
          # ArgoCD server runs in insecure mode (--insecure), uses HTTP on port 80
        },
        var.enable_tls ? {
          "cert-manager.io/cluster-issuer" = var.cluster_issuer
        } : {}
      )
    }
    spec = {
      ingressClassName = "traefik"
      tls = var.enable_tls ? [
        {
          hosts      = [var.argocd_domain]
          secretName = "argocd-tls"
        }
      ] : null
      rules = [
        {
          host = var.argocd_domain
          http = {
            paths = [
              {
                path     = "/"
                pathType = "Prefix"
                backend = {
                  service = {
                    name = "argocd-server"
                    port = {
                      number = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }
}
