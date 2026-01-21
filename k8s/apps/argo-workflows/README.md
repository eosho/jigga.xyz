# Argo Workflows

Kubernetes-native workflow orchestration engine for complex job scheduling, CI/CD pipelines, and data processing.

## Overview

Argo Workflows is a CNCF-graduated project that enables:
- **CronWorkflow** - Scheduled workflow execution
- **WorkflowTemplate** - Reusable workflow definitions
- **ClusterWorkflowTemplate** - Cluster-wide workflow templates
- **Workflow** - One-time workflow execution

## Components

| Component | Replicas | Purpose |
|-----------|----------|---------|
| Workflow Controller | 2 | Manages workflow execution |
| Argo Server | 2 | Web UI and API |

## Access

- **UI**: https://workflows.jigga.xyz
- **API**: https://workflows.jigga.xyz/api/v1

## Namespaces

Workflows can run in:
- `argo-workflows` (default)
- `default`

To add more namespaces, update `controller.workflowNamespaces` in values.yaml.

## Usage Examples

### Simple Workflow

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: hello-world-
  namespace: argo-workflows
spec:
  entrypoint: whalesay
  serviceAccountName: argo-workflow
  templates:
    - name: whalesay
      container:
        image: docker/whalesay
        command: [cowsay]
        args: ["Hello World"]
```

### CronWorkflow (Scheduled)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: CronWorkflow
metadata:
  name: daily-backup
  namespace: argo-workflows
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  concurrencyPolicy: Forbid
  workflowSpec:
    entrypoint: backup
    serviceAccountName: argo-workflow
    templates:
      - name: backup
        container:
          image: postgres:18
          command: ["/bin/sh", "-c"]
          args: ["pg_dump ..."]
```

## Configuration

| Setting | Value |
|---------|-------|
| Helm Chart | argo-workflows v0.47.0 |
| App Version | v3.7.7 |
| Auth Mode | server (basic) |
| Workflow TTL | 1 day (success: 12h, failure: 2d) |
| Pod GC | OnPodCompletion |

## Metrics

Prometheus metrics available at:
- Controller: `:9090/metrics`
- Server: `:2746/metrics`
