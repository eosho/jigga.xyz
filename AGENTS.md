# AGENTS.md

This repository is managed using **GitOps-first principles** and is intended to be worked on by both humans and AI-assisted development tools.

This document defines **hard constraints and expectations** for any automated or assisted changes made to this repository.

---

## Core Principles

- **Git is the source of truth**
- **Clusters select apps; apps never select clusters**
- Prefer **plain Kubernetes YAML + Kustomize**
- **Helm is optional**, not the default
- **Secrets must be encrypted** (SOPS + AGE)
- Avoid unnecessary abstraction and over-modularization
- Favor clarity, debuggability, and long-term maintainability

---

## Repository Structure

The repository is organized by **responsibility and lifecycle**:

```
k8s/
├── bootstrap/        # GitOps bootstrap (Flux installation)
├── clusters/         # Cluster-specific wiring and app selection
├── apps/             # Application definitions
└── platform/         # Shared infrastructure (ingress, cert-manager, monitoring)
```

### Responsibilities

| Directory     | Purpose |
|--------------|---------|
| `bootstrap/` | Installs GitOps tooling (Flux) |
| `clusters/`  | Declares which apps run in which cluster |
| `apps/`      | Self-contained application definitions |
| `platform/`  | Shared, cluster-wide services |

---

## GitOps Model

### Cluster intent vs app intent

- **Cluster intent** lives under `k8s/clusters/<cluster-name>/`
- **App intent** lives under `k8s/apps/<app-name>/`

Apps must remain **cluster-agnostic**.

### Golden rule

> **Clusters select apps; apps never select clusters.**

---

## Application Layout (Non-Helm)

**Default and preferred pattern**

Each non-Helm application **must** follow this structure:

```
app-name/
├── namespace.yaml
├── config/
│   ├── configmap.yaml
│   └── secret.yaml
├── workload/
│   └── deployment.yaml | statefulset.yaml
├── networking/
│   ├── services.yaml
│   └── ingress.yaml
└── kustomization.yaml
```

### Rules

- One application per directory
- Exactly one `kustomization.yaml` per application (at the app root)
- Group files by **lifecycle**, not Kubernetes kind
- Keep files together if they always change together
- Do not introduce overlays or patches unless there is a clear environment-driven need

### Kustomize requirements

- App-level `kustomization.yaml` must only reference files inside the app directory
- Avoid nested `kustomization.yaml` files unless explicitly required

---

## Helm Usage

Helm **is allowed**, but only when it is the right tool.

### When Helm is appropriate

- Platform components (monitoring, ingress, cert-manager)
- Third-party software with large configuration matrices
- Well-maintained upstream charts

### Helm rules

- Helm must be managed via **Flux HelmRelease** (or Argo Helm sources if Argo is used)
- Helm apps still live under `k8s/apps/`
- Values must be **explicit and minimal**
- Helm is an implementation detail, not a repo-wide decision
- Helm charts may be flattened to raw YAML later if needed

### Helm app structure (Flux example)

```
app-name/
├── namespace.yaml
├── helmrelease.yaml
└── kustomization.yaml
```

---

## GitOps Rules (Operational)

- Do **not** use `kubectl apply` for application changes
- All application changes must go through Git (PR or commit workflow)
- Flux or Argo reconciles cluster state continuously
- Drift should be corrected automatically by the GitOps controller
- Removing an app is done by deleting its directory and committing the change

---

## kubectl Usage Rules (Windows, WSL, Linux, macOS)

### General rules (all platforms)

- `kubectl` is **read-first**, not write-first
- Prefer:
  - `kubectl get`
  - `kubectl describe`
  - `kubectl logs`
  - `kubectl diff`
- Avoid:
  - `kubectl apply`
  - `kubectl delete`
  - `kubectl edit`
- Any persistent change **must** be made via Git and reconciled by GitOps

---

### Windows (native PowerShell / CMD)

Allowed:
- `kubectl get`, `describe`, `logs`, `top`
- Context inspection and troubleshooting
- Viewing live state vs Git state

Not allowed:
- `kubectl apply`
- `kubectl patch`
- `kubectl edit`
- Manual resource creation or deletion

Notes:
- PowerShell quoting issues are common; prefer WSL for complex commands
- Ensure the correct kubecontext is selected before running commands

---

### Windows with WSL (recommended)

**Preferred Windows workflow**

- Use WSL (Ubuntu or similar) as the primary Kubernetes shell
- Run `kubectl`, `flux`, `sops`, `kustomize`, and `age` inside WSL
- Store kubeconfig in WSL filesystem

Allowed:
- Read-only inspection
- Debugging (`logs`, `exec`, `port-forward`)
- `kubectl diff` for validation

Not allowed:
- Applying manifests outside GitOps
- Editing live resources as a substitute for Git changes

Rationale:
- Linux tooling behaves consistently
- Matches CI and cluster-side tooling
- Avoids Windows-specific edge cases

---

### Linux (bash/zsh) and macOS (bash/zsh)

**Canonical environment**

- All documentation and commands assume a POSIX shell
- This is the reference environment for correctness

Allowed:
- Inspection and debugging
- Temporary diagnostics (`exec`, `port-forward`)
- Validation (`kubectl diff`, `kustomize build`)

Not allowed:
- Manual lifecycle management of GitOps-managed apps
- Using `kubectl` to bypass Git

---

### Emergency exception (rare)

In the event of an **active incident**:

- `kubectl` may be used to:
  - scale a workload temporarily
  - stop a runaway pod
- Any emergency action **must** be:
  1. Documented
  2. Reconciled back into Git immediately after

> Git must always be restored as the source of truth.

---

## Secrets & Security

### Hard rules

- **No plaintext secrets are allowed in Git**
- All secrets must be encrypted using **SOPS + AGE**
- The AGE private key must never be committed

### Expectations

- Secrets belong under `config/secret.yaml`
- Encrypted secrets are committed as normal YAML with SOPS metadata
- Namespace isolation is required

---

## Resource & Reliability Conventions

### Resource requests and limits

- Workloads should define **resources.requests** and **resources.limits**
- Avoid deploying workloads without them unless explicitly justified

### Probes

- Define readiness and liveness probes where applicable
- Tune probes to avoid flapping on cold starts or slow storage

---

## Networking Conventions

- Prefer Ingress for HTTP/HTTPS exposure
- Prefer LoadBalancer services only when explicitly required (e.g., MQTT/TCP)
- Networking resources belong under `networking/`

---

## AI Contribution Guidelines

When making changes (especially via AI-assisted workflows):

- Follow existing patterns exactly
- Do not invent new folder structures
- Do not introduce Helm unless explicitly requested or justified
- Do not introduce unnecessary abstraction
- Prefer small, reviewable diffs
- If unsure, bias toward clarity and explicitness

---

## Common Tasks

### Add a new non-Helm app

1. Copy `k8s/apps/_template/` to `k8s/apps/<new-app>/`
2. Fill in manifests under `config/`, `workload/`, and `networking/`
3. Update the app root `kustomization.yaml`
4. Commit and push

### Add a Helm-managed app (Flux)

1. Create `k8s/apps/<app>/namespace.yaml`
2. Add `helmrelease.yaml` with minimal values
3. Reference them in the app `kustomization.yaml`
4. Commit and push

---

## Non-Goals

This repository does not aim to:

- Provide long tutorial-style documentation in AGENTS.md
- Store credentials or environment-specific secrets in plaintext
- Encode per-cluster logic inside app directories
- Over-optimize for templating or abstraction
