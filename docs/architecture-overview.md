# Architecture Overview

**Navigation:** [Main README](../README.md) | [Documentation Index](README.md) | [Network Architecture](network-architecture.md)

Complete architecture documentation for the K3s homelab infrastructure running on Proxmox.

## Infrastructure Diagram

```mermaid
flowchart TB
    subgraph Internet
        USER[Users]
    end

    subgraph Access["Access Layer"]
        CF[Cloudflare Tunnel<br/>*.jigga.xyz]
        TS[Tailscale VPN<br/>*.int.jigga.xyz]
    end

    subgraph HomeNetwork["Home Network - 192.168.7.0/24"]
        subgraph Proxmox["Proxmox Cluster"]
            PVE1[pve-alpha<br/>192.168.7.233]
            PVE2[pve-beta<br/>192.168.7.234]
            PVE3[pve-gamma<br/>192.168.7.235]

            subgraph Ceph["Ceph Storage"]
                POOL[(kubernetes pool<br/>RBD Block Storage)]
            end
        end

        subgraph K3s["K3s Cluster"]
            CTRL[ichigo<br/>Control Plane<br/>192.168.7.223]
            W1[naruto<br/>Worker<br/>192.168.7.224]
            W2[tanjiro<br/>Worker<br/>192.168.7.225]

            subgraph MetalLB["MetalLB Pool"]
                LB[192.168.7.230-235<br/>Traefik @ .230]
            end
        end
    end

    USER --> CF
    USER --> TS
    CF --> LB
    TS --> LB
    LB --> CTRL
    LB --> W1
    LB --> W2
    PVE1 --> POOL
    PVE2 --> POOL
    PVE3 --> POOL
    POOL --> CTRL
    POOL --> W1
    POOL --> W2
```

## Component Overview

### Proxmox Hypervisor Layer

| Component | Description |
|-----------|-------------|
| **Proxmox VE** | Virtualization platform (3-node cluster) |
| **Ceph Storage** | Distributed storage for VM disks and K8s PVs |
| **SDN (VXLAN)** | Software-defined overlay network for VM inter-communication |

### Kubernetes Layer

| Component | Description |
|-----------|-------------|
| **K3s** | Lightweight Kubernetes distribution |
| **MetalLB** | Bare-metal LoadBalancer (L2 mode) |
| **Traefik** | Ingress controller with automatic TLS |
| **Cert-Manager** | Let's Encrypt certificate automation |
| **Ceph CSI** | Storage provisioner for PersistentVolumes |

### Access Layer

| Component | Description |
|-----------|-------------|
| **Cloudflare Tunnel** | Zero-trust public access (no exposed ports) |
| **Tailscale** | Mesh VPN for secure internal access |
| **DNS (Cloudflare)** | Authoritative DNS with automatic records |

## Resource Allocation

### Total Cluster Resources

| Resource | Total | Per Node |
|----------|-------|----------|
| vCPUs | 20 cores | 8, 8, 4 |
| Memory | 48 GB | 16 GB |
| Storage | 384 GB | 128 GB |

### Kubernetes Network CIDRs

| Network | CIDR | Purpose |
|---------|------|---------|
| Pod Network | 10.42.0.0/16 | Container IPs |
| Service Network | 10.43.0.0/16 | ClusterIP services |
| MetalLB Pool | 192.168.7.224/29 | LoadBalancer IPs |

## Deployed Applications

### Infrastructure Services

| Service | Namespace | Access |
|---------|-----------|--------|
| Traefik | kube-system | LoadBalancer (192.168.7.230) |
| Cert-Manager | cert-manager | Internal |
| MetalLB | metallb-system | Internal |
| ArgoCD | argocd | Internal (argocd.int.jigga.xyz) |

### Monitoring Stack

| Service | Namespace | Access |
|---------|-----------|--------|
| Prometheus | monitoring | Internal |
| Grafana | monitoring | Internal (grafana.int.jigga.xyz) |
| Loki | monitoring | Internal |
| Alertmanager | monitoring | Internal |

### Applications

| Service | Namespace | Access |
|---------|-----------|--------|
| Vaultwarden | vaultwarden | Public (passwords.jigga.xyz) |
| Homepage | web | Public (jigga.xyz) |
| Vault | vault | Internal |

## Technology Stack

```mermaid
block-beta
    columns 1

    block:apps["Applications"]
        A1["Vaultwarden"] A2["Homepage"] A3["Grafana"] A4["ArgoCD"] A5["Vault"]
    end

    block:k8s["Kubernetes - K3s"]
        K1["Deployments"] K2["Services"] K3["Ingress"] K4["PersistentVolumes"]
    end

    block:net["Networking"]
        N1["Traefik"] N2["MetalLB"] N3["Cert-Manager"] N4["CoreDNS"]
    end

    block:storage["Storage"]
        S1["Ceph RBD CSI"] S2["PersistentVolumeClaims"]
    end

    block:virt["Virtualization"]
        V1["Proxmox VE"] V2["Cloud-Init VMs"] V3["Ceph Storage"]
    end

    block:iac["Infrastructure as Code"]
        I1["Terraform"] I2["GitOps - ArgoCD"] I3["Helm Charts"]
    end
```

## Related Documentation

- [Network Architecture](network-architecture.md) - Detailed networking documentation
- [SDN Configuration](sdn-configuration.md) - Proxmox SDN setup
- [Adding New Applications](adding-new-applications.md) - Deployment guide
- [Maintenance Guide](maintenance-guide.md) - Day-2 operations
