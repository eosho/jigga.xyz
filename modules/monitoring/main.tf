# Monitoring Stack Module

# Kube Prometheus Stack (includes Prometheus, Alertmanager, and Grafana)
resource "helm_release" "kube_prometheus_stack" {
  count = var.deploy_monitoring ? 1 : 0

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "81.6.9"
  namespace  = "monitoring"

  create_namespace = true
  wait             = true
  timeout          = 900 # 15 minutes

  values = [<<EOF
# CRDs managed by chart, upgrade job disabled (preview feature, prone to failures)
# CRDs are still upgraded when chart version changes
crds:
  enabled: true
  upgradeJob:
    enabled: false

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
  # Additional data sources
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki-gateway.monitoring.svc.cluster.local
    # - name: Tempo
    #   type: tempo
    #   url: http://tempo.monitoring.svc.cluster.local:3200

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
        - receiver: 'null'
          matchers:
            - alertname = "InfoInhibitor"
        - receiver: 'discord'
          continue: true
    inhibit_rules:
      - source_matchers:
          - severity = "info"
        target_matchers:
          - severity = "info"
        equal: ['namespace', 'alertname']
      - source_matchers:
          - alertname = "InfoInhibitor"
        target_matchers:
          - severity = "info"
        equal: ['namespace']
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


# Loki Stack for Log Collection
resource "helm_release" "loki" {
  count = var.deploy_monitoring ? 1 : 0

  depends_on = [helm_release.kube_prometheus_stack]

  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.51.0"
  namespace  = "monitoring"

  wait    = true
  timeout = 600 # 10 minutes

  values = [<<EOF
# Deploy mode: singleBinary for small clusters
deploymentMode: SingleBinary

loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: 'filesystem'
  schemaConfig:
    configs:
      - from: 2020-10-24
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: index_
          period: 24h
  limits_config:
    retention_period: 168h
    volume_enabled: true

# Single binary deployment
singleBinary:
  replicas: 1
  persistence:
    storageClass: ceph-rbd
    size: 5Gi
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

# Disable distributed components
read:
  replicas: 0
write:
  replicas: 0
backend:
  replicas: 0

# Gateway routes to single binary
gateway:
  enabled: true

# Disable caches not needed in single binary
chunksCache:
  enabled: false
resultsCache:
  enabled: false

# Disable canary
lokiCanary:
  enabled: false

# Disable helm test
test:
  enabled: false

# Enable ServiceMonitor for Prometheus scraping
monitoring:
  serviceMonitor:
    enabled: true
    labels:
      release: kube-prometheus-stack
  selfMonitoring:
    enabled: false
    grafanaAgent:
      installOperator: false
EOF
  ]
}

# Grafana Alloy for Log Collection (replaces deprecated Promtail)
resource "helm_release" "alloy" {
  count = var.deploy_monitoring ? 1 : 0

  depends_on = [helm_release.loki]

  name       = "alloy"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = "1.5.2"
  namespace  = "monitoring"

  wait    = true
  timeout = 300 # 5 minutes

  values = [<<EOF
alloy:
  configMap:
    create: true
    content: |
      logging {
        level  = "info"
        format = "logfmt"
      }

      // Discover all pods in the cluster
      discovery.kubernetes "pods" {
        role = "pod"
      }

      // Relabel discovered pods - add namespace, pod, container labels
      // and Argo Workflow specific labels for log correlation
      discovery.relabel "pods" {
        targets = discovery.kubernetes.pods.targets

        // Basic Kubernetes labels
        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          target_label  = "namespace"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_name"]
          target_label  = "pod"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_container_name"]
          target_label  = "container"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_node_name"]
          target_label  = "node_name"
        }
        // App label for general filtering
        rule {
          source_labels = ["__meta_kubernetes_pod_label_app"]
          target_label  = "app"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
          target_label  = "app"
        }
        // service_name label for Grafana Explore Logs UI
        // Priority: app.kubernetes.io/name > app label > container name
        rule {
          source_labels = ["__meta_kubernetes_pod_container_name"]
          target_label  = "service_name"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_label_app"]
          regex         = "(.+)"
          target_label  = "service_name"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
          regex         = "(.+)"
          target_label  = "service_name"
        }
        // Argo Workflows labels for log querying from UI
        rule {
          source_labels = ["__meta_kubernetes_pod_label_workflows_argoproj_io_workflow"]
          target_label  = "workflow"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_label_workflows_argoproj_io_workflow_template"]
          target_label  = "workflow_template"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_annotation_workflows_argoproj_io_node_name"]
          target_label  = "argo_node_name"
        }
      }

      // Collect logs from discovered pods
      loki.source.kubernetes "pods" {
        targets    = discovery.relabel.pods.output
        forward_to = [loki.write.default.receiver]
      }

      // Send logs to Loki
      loki.write "default" {
        endpoint {
          url = "http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push"
        }
      }
  mounts:
    varlog: true
    dockercontainers: true
  resources:
    requests:
      cpu: 10m
      memory: 64Mi
    limits:
      cpu: 200m
      memory: 256Mi

controller:
  type: daemonset

# Enable ServiceMonitor for Prometheus scraping
serviceMonitor:
  enabled: true
  additionalLabels:
    release: kube-prometheus-stack
EOF
  ]
}

# Tempo for Distributed Tracing (DISABLED - uncomment to enable)
# resource "helm_release" "tempo" {
#   count = var.deploy_monitoring ? 1 : 0
#
#   depends_on = [helm_release.kube_prometheus_stack]
#
#   name       = "tempo"
#   repository = "https://grafana.github.io/helm-charts"
#   chart      = "tempo"
#   version    = "1.24.3"
#   namespace  = "monitoring"
#
#   wait    = true
#   timeout = 300 # 5 minutes
#
#   values = [<<EOF
# tempo:
#   reportingEnabled: false
#   retention: 72h
#   storage:
#     trace:
#       backend: local
#       local:
#         path: /var/tempo/traces
#       wal:
#         path: /var/tempo/wal
#   # OTLP receiver for traces
#   receivers:
#     otlp:
#       protocols:
#         grpc:
#           endpoint: "0.0.0.0:4317"
#         http:
#           endpoint: "0.0.0.0:4318"
#
# # Persistence for trace storage
# persistence:
#   enabled: true
#   storageClassName: ceph-rbd
#   size: 5Gi
#
# # Resources
# resources:
#   requests:
#     cpu: 50m
#     memory: 128Mi
#   limits:
#     cpu: 500m
#     memory: 512Mi
#
# # ServiceMonitor for Prometheus
# serviceMonitor:
#   enabled: true
#   additionalLabels:
#     release: kube-prometheus-stack
# EOF
#   ]
# }

# Note: Grafana ingress is defined in the ingress module for centralized management