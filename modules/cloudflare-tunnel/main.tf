# Cloudflare Tunnel Module
# Deploys cloudflared to expose services publicly via Cloudflare's network

resource "kubernetes_namespace_v1" "cloudflare" {
  count = var.deploy_cloudflare_tunnel ? 1 : 0

  metadata {
    name = "cloudflare"
    labels = {
      "app.kubernetes.io/name"       = "cloudflare-tunnel"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# Tunnel credentials secret
resource "kubernetes_secret_v1" "tunnel_credentials" {
  count = var.deploy_cloudflare_tunnel ? 1 : 0

  metadata {
    name      = "cloudflare-tunnel-credentials"
    namespace = kubernetes_namespace_v1.cloudflare[0].metadata[0].name
  }

  data = {
    "credentials.json" = jsonencode({
      AccountTag   = var.tunnel_credentials.account_tag
      TunnelSecret = var.tunnel_credentials.tunnel_secret
      TunnelID     = var.tunnel_credentials.tunnel_id
    })
  }

  type = "Opaque"
}

# Tunnel configuration
resource "kubernetes_config_map_v1" "tunnel_config" {
  count = var.deploy_cloudflare_tunnel ? 1 : 0

  metadata {
    name      = "cloudflare-tunnel-config"
    namespace = kubernetes_namespace_v1.cloudflare[0].metadata[0].name
  }

  data = {
    "config.yaml" = yamlencode({
      tunnel           = var.tunnel_name
      credentials-file = "/etc/cloudflared/credentials.json"
      no-autoupdate    = true
      metrics          = "0.0.0.0:2000"
      ingress = concat(
        [for rule in var.ingress_rules : {
          hostname = rule.hostname
          service  = rule.service
        }],
        [{ service = "http_status:404" }]
      )
    })
  }
}

# Cloudflared deployment
resource "kubernetes_deployment_v1" "cloudflared" {
  count = var.deploy_cloudflare_tunnel ? 1 : 0

  metadata {
    name      = "cloudflared"
    namespace = kubernetes_namespace_v1.cloudflare[0].metadata[0].name
    labels = {
      app = "cloudflared"
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = "cloudflared"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
      }

      spec {
        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:latest"

          args = [
            "tunnel",
            "--config",
            "/etc/cloudflared/config.yaml",
            "run"
          ]

          port {
            container_port = 2000
            name           = "metrics"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/cloudflared/config.yaml"
            sub_path   = "config.yaml"
            read_only  = true
          }

          volume_mount {
            name       = "credentials"
            mount_path = "/etc/cloudflared/credentials.json"
            sub_path   = "credentials.json"
            read_only  = true
          }

          liveness_probe {
            http_get {
              path = "/ready"
              port = 2000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = 2000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.tunnel_config[0].metadata[0].name
          }
        }

        volume {
          name = "credentials"
          secret {
            secret_name = kubernetes_secret_v1.tunnel_credentials[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Metrics service for monitoring
resource "kubernetes_service_v1" "cloudflared_metrics" {
  count = var.deploy_cloudflare_tunnel ? 1 : 0

  metadata {
    name      = "cloudflared-metrics"
    namespace = kubernetes_namespace_v1.cloudflare[0].metadata[0].name
    labels = {
      app = "cloudflared"
    }
  }

  spec {
    selector = {
      app = "cloudflared"
    }

    port {
      name        = "metrics"
      port        = 2000
      target_port = 2000
    }
  }
}

# DNS Records for tunnel hostnames
# Creates CNAME records pointing to the tunnel
resource "cloudflare_dns_record" "tunnel_dns" {
  for_each = var.deploy_cloudflare_tunnel && var.create_dns_records && var.cloudflare_zone_id != "" ? {
    for rule in var.ingress_rules : rule.hostname => rule
  } : {}

  zone_id = var.cloudflare_zone_id
  name    = each.value.hostname
  content = "${var.tunnel_credentials.tunnel_id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1 # Auto TTL when proxied
  comment = "Managed by Terraform - Cloudflare Tunnel"
}
