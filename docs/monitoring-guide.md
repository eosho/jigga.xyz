# Monitoring Documentation

This directory contains documentation for the monitoring and observability stack.

## Guides

| Guide | Description |
|-------|-------------|
| [Overview](overview.md) | Architecture and components |
| [Prometheus](prometheus.md) | Metrics collection, PromQL queries, targets |
| [Alertmanager](alertmanager.md) | Alert routing, silencing, configuration |
| [Loki](loki.md) | Log aggregation, LogQL queries |
| [Grafana](grafana.md) | Dashboards and visualization |
| [Metrics Reference](metrics-reference.md) | Common PromQL queries by service |

## Quick Links

| Service | URL |
|---------|-----|
| Grafana | https://grafana.int.jigga.xyz |
| Prometheus | https://prometheus.int.jigga.xyz |
| Alertmanager | https://alertmanager.int.jigga.xyz |

## Stack Components

```
┌─────────────────────────────────────────────────────────────┐
│                        Grafana                              │
│                   (Dashboards & Explore)                    │
└─────────────────────┬───────────────────┬───────────────────┘
                      │                   │
              ┌───────▼───────┐   ┌───────▼───────┐
              │  Prometheus   │   │     Loki      │
              │   (Metrics)   │   │    (Logs)     │
              └───────┬───────┘   └───────┬───────┘
                      │                   │
        ┌─────────────┼─────────────┐     │
        │             │             │     │
        ▼             ▼             ▼     ▼
┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────┐
│  Node     │ │  kube-    │ │  Service  │ │   Alloy   │
│ Exporter  │ │  state-   │ │  Monitors │ │(DaemonSet)│
└───────────┘ │  metrics  │ └───────────┘ └───────────┘
              └───────────┘
```
