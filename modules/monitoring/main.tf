# Monitoring Stack Module

# Kube Prometheus Stack (includes Prometheus, Alertmanager, and Grafana)
resource "helm_release" "kube_prometheus_stack" {
  count = var.deploy_monitoring ? 1 : 0

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "80.10.0"
  namespace  = "monitoring"

  create_namespace = true
  wait             = true
  timeout          = 900 # 15 minutes

  values = [<<EOF
# Enable CRD upgrade job to keep CRDs in sync with chart version
crds:
  enabled: true
  upgradeJob:
    enabled: true

grafana:
  adminPassword: "${var.grafana_admin_password}"
  persistence:
    enabled: true
    storageClassName: ceph-rbd
    accessModes:
      - ReadWriteOnce
    size: 5Gi
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards/default
  dashboards:
    default:
      k8s-system-resources:
        gnetId: 15759
        revision: 1
        datasource: Prometheus
      k8s-cluster-resources:
        gnetId: 15760
        revision: 1
        datasource: Prometheus
      k8s-node-resources:
        gnetId: 15761
        revision: 1
        datasource: Prometheus
      node-exporter-full:
        gnetId: 1860
        revision: 30
        datasource: Prometheus
  # Additional data sources (DISABLED - Loki/Tempo not deployed)
  # additionalDataSources:
  #   - name: Loki
  #     type: loki
  #     url: http://loki-gateway.monitoring.svc.cluster.local
  #   - name: Tempo
  #     type: tempo
  #     url: http://tempo.monitoring.svc.cluster.local:3100

prometheus:
  prometheusSpec:
    retention: 7d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: ceph-rbd
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    resources:
      requests:
        memory: 512Mi
        cpu: 500m
      limits:
        memory: 2Gi
        cpu: 1000m

# Alertmanager configuration
alertmanager:
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: 'discord'
      routes:
        - receiver: 'null'
          matchers:
            - alertname = "Watchdog"
        - receiver: 'discord'
          continue: true
    receivers:
      - name: 'null'
      - name: 'discord'
        discord_configs:
          - webhook_url: '${var.alertmanager_discord_webhook_url}'
            title: '{{ template "discord.default.title" . }}'
            message: '{{ template "discord.default.message" . }}'
    templates:
      - '/etc/alertmanager/config/*.tmpl'

# K3s embedded etcd with --etcd-expose-metrics binds to 0.0.0.0:2381
kubeEtcd:
  enabled: true
  service:
    enabled: false  # We create manual service/endpoints below

# K3s also doesn't expose kube-scheduler and kube-controller-manager metrics by default
kubeScheduler:
  enabled: false
kubeControllerManager:
  enabled: false

# K3s proxy metrics are exposed differently
kubeProxy:
  enabled: false
EOF
  ]
}

# Manual Service and Endpoints for K3s etcd metrics
# K3s embedded etcd runs on the host, not as a pod, so we need manual endpoints
resource "kubernetes_service_v1" "etcd_metrics" {
  count = var.deploy_monitoring ? 1 : 0

  metadata {
    name      = "kube-prometheus-stack-kube-etcd"
    namespace = "kube-system"
    labels = {
      "app"                          = "kube-prometheus-stack-kube-etcd"
      "app.kubernetes.io/managed-by" = "Terraform"
      "jobLabel"                     = "kube-etcd"
    }
  }

  spec {
    type       = "ClusterIP"
    cluster_ip = "None" # Headless service

    port {
      name        = "http-metrics"
      port        = 2381
      target_port = 2381
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_endpoints_v1" "etcd_metrics" {
  count = var.deploy_monitoring ? 1 : 0

  metadata {
    name      = "kube-prometheus-stack-kube-etcd"
    namespace = "kube-system"
    labels = {
      "app"                          = "kube-prometheus-stack-kube-etcd"
      "app.kubernetes.io/managed-by" = "Terraform"
    }
  }

  subset {
    address {
      ip = var.k3s_server_ip # Control plane node IP
    }

    port {
      name     = "http-metrics"
      port     = 2381
      protocol = "TCP"
    }
  }
}


# Loki Stack for Log Collection (DISABLED - uncomment to enable)
# resource "helm_release" "loki" {
#   count = var.deploy_monitoring ? 1 : 0
#
#   depends_on = [helm_release.kube_prometheus_stack]
#
#   name       = "loki"
#   repository = "https://grafana.github.io/helm-charts"
#   chart      = "loki"
#   version    = "5.8.9"
#   namespace  = "monitoring"
#
#   wait  = true
#   timeout = 600 # 10 minutes
#
#   values = [<<EOF
# loki:
#   auth_enabled: false
#   commonConfig:
#     replication_factor: 1
#   storage:
#     type: 'filesystem'
#   schemaConfig:
#     configs:
#       - from: 2020-10-24
#         store: boltdb-shipper
#         object_store: filesystem
#         schema: v11
#         index:
#           prefix: index_
#           period: 24h
#   storageConfig:
#     boltdb_shipper:
#       active_index_directory: /data/loki/boltdb-shipper-active
#       cache_location: /data/loki/boltdb-shipper-cache
#       cache_ttl: 24h
#       shared_store: filesystem
#     filesystem:
#       directory: /data/loki/chunks
#
# # Use single binary mode for simplicity
# singleBinary:
#   replicas: 1
#   persistence:
#     storageClass: ceph-rbd
#     size: 5Gi
#
# # Disable scalable deployment
# read:
#   enabled: false
# write:
#   enabled: false
# backend:
#   enabled: false
#
# gateway:
#   enabled: true
# EOF
#   ]
# }

# Promtail for Log Collection (DISABLED - uncomment to enable)
# resource "helm_release" "promtail" {
#   count = var.deploy_monitoring ? 1 : 0
#
#   depends_on = [helm_release.loki]
#
#   name       = "promtail"
#   repository = "https://grafana.github.io/helm-charts"
#   chart      = "promtail"
#   version    = "6.15.3"
#   namespace  = "monitoring"
#
#   wait = true
#   timeout = 300 # 5 minutes
#
#   values = [<<EOF
# config:
#   clients:
#     - url: http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push
# EOF
#   ]
# }

# Tempo for Distributed Tracing (DISABLED - uncomment to enable)
# resource "helm_release" "tempo" {
#   count = var.deploy_monitoring ? 1 : 0
#
#   depends_on = [helm_release.kube_prometheus_stack]
#
#   name       = "tempo"
#   repository = "https://grafana.github.io/helm-charts"
#   chart      = "tempo"
#   version    = "1.7.1"  # Updated version
#   namespace  = "monitoring"
#
#   wait  = true
#   timeout = 300 # 5 minutes
#
#   values = [<<EOF
# tempo:
#   storage:
#     trace:
#       backend: local
#       local:
#         path: /var/tempo/traces
#   retention: 24h
#   reportingEnabled: false
#
# multitenancy:
#   enabled: false
#
# resources:
#   requests:
#     cpu: 100m
#     memory: 128Mi
#   limits:
#     cpu: 1
#     memory: 1Gi
# EOF
#   ]
# }

# Note: Grafana ingress is defined in the ingress module for centralized management