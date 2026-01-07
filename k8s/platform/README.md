# Platform

This directory contains **configuration artifacts** for platform-level infrastructure components.

> ⚠️ **Important:** This directory does NOT contain lifecycle ownership. Helm chart installations are managed by Terraform in `modules/`.

## What Belongs Here

- Custom alerting rules (PrometheusRule CRDs)
- Grafana dashboards and configurations
- MetalLB IP pool configurations
- Any platform-level Kubernetes resources NOT managed by Helm/K3s

## What Does NOT Belong Here

- Helm chart installations (managed by Terraform)
- Application deployments (belong in `k8s/apps/`)
- Cluster-specific configurations (belong in `k8s/clusters/`)

## Directory Structure

```
platform/
├── monitoring/
│   └── alerts/           # PrometheusRule CRDs
├── grafana/
│   └── config/           # Dashboards, auth configs
└── metallb/
    └── config/           # IP address pools
```

> **Note:** Traefik is managed by K3s's built-in Helm controller.
