# Network Architecture

**Navigation:** [Main README](../README.md) | [Documentation Index](README.md) | [Architecture Overview](architecture-overview.md)

Comprehensive network documentation for the K3s homelab infrastructure.

## Network Topology

```mermaid
flowchart TB
    subgraph Internet["Internet"]
        USER[Users/Clients]
    end

    subgraph CloudServices["Cloud Services"]
        subgraph Cloudflare["Cloudflare Edge"]
            CF_EDGE[DDoS Protection<br/>WAF<br/>SSL Termination]
        end

        subgraph Tailscale["Tailscale Coordination"]
            TS_COORD[WireGuard-based<br/>NAT Traversal<br/>MagicDNS]
        end
    end

    subgraph K3sCluster["K3s Cluster Network"]
        subgraph IngressLayer["Ingress Layer"]
            CFD[cloudflared pods<br/>Namespace: cloudflare]
            TSO[tailscale-operator<br/>k3s-router<br/>Namespace: tailscale]
        end

        subgraph LoadBalancer["Load Balancer"]
            TRAEFIK[Traefik Ingress<br/>192.168.7.230]
        end

        subgraph ServiceNetwork["Service Network - 10.43.0.0/16"]
            SVC1[argocd-server]
            SVC2[grafana]
            SVC3[vaultwarden]
            SVC4[prometheus]
        end

        subgraph PodNetwork["Pod Network - 10.42.0.0/16"]
            POD1[ichigo: 10.42.0.0/24]
            POD2[naruto: 10.42.1.0/24]
            POD3[tanjiro: 10.42.2.0/24]
        end
    end

    USER --> CF_EDGE
    USER --> TS_COORD
    CF_EDGE -->|Tunnel| CFD
    TS_COORD -->|WireGuard| TSO
    CFD --> TRAEFIK
    TSO --> TRAEFIK
    TRAEFIK --> SVC1
    TRAEFIK --> SVC2
    TRAEFIK --> SVC3
    TRAEFIK --> SVC4
    SVC1 --> POD1
    SVC2 --> POD2
    SVC3 --> POD3
```

## IP Address Allocation

### Home Network (192.168.7.0/24)

| IP Range | Purpose | Devices |
|----------|---------|---------|
| 192.168.7.1 | Gateway | Router |
| 192.168.7.223-225 | K3s Nodes | ichigo, naruto, tanjiro |
| 192.168.7.230-235 | MetalLB Pool | LoadBalancer services |
| 192.168.7.233-235 | Proxmox Hosts | pve-alpha, beta, gamma |

### SDN Private Network (10.0.0.0/24)

| IP | Purpose |
|----|---------|
| 10.0.0.1 | Gateway (virtual) |
| 10.0.0.10 | ichigo (private) |
| 10.0.0.11 | naruto (private) |
| 10.0.0.12 | tanjiro (private) |

### Kubernetes Networks

| Network | CIDR | Purpose |
|---------|------|---------|
| Pod Network | 10.42.0.0/16 | Container networking |
| Service Network | 10.43.0.0/16 | ClusterIP services |
| CoreDNS | 10.43.0.10 | Cluster DNS |

### Tailscale Networks

| Network | Purpose |
|---------|---------|
| 100.x.x.x/8 | Tailscale device IPs |
| Advertised Routes | 10.42.0.0/16, 10.43.0.0/16, 192.168.7.224/29 |

## Traffic Flow Diagrams

### Public Access via Cloudflare Tunnel

```mermaid
sequenceDiagram
    participant User
    participant Cloudflare as Cloudflare Edge
    participant CFD as cloudflared Pod
    participant SVC as K8s Service
    participant App as App Pod

    User->>Cloudflare: https://passwords.jigga.xyz
    Note over Cloudflare: SSL Termination<br/>DDoS Protection<br/>WAF Rules
    Cloudflare->>CFD: Encrypted Tunnel
    Note over CFD: Route lookup:<br/>passwords.jigga.xyz -><br/>vaultwarden.vaultwarden:80
    CFD->>SVC: HTTP request
    SVC->>App: Load balanced
    App-->>User: Response via same path
```

**Flow Description:**
1. User requests `https://passwords.jigga.xyz`
2. DNS resolves to Cloudflare Edge (CNAME to tunnel.cfargotunnel.com)
3. Cloudflare terminates SSL, applies security rules
4. Request forwarded through encrypted tunnel to cloudflared pod
5. cloudflared looks up hostname in ConfigMap
6. Routes to internal service: `http://vaultwarden.vaultwarden:80`
7. Response returns via same path

### Internal Access via Tailscale VPN

```mermaid
sequenceDiagram
    participant Device as Mobile Device
    participant TSNet as Tailscale Network
    participant Router as k3s-router Pod
    participant Traefik
    participant SVC as K8s Service
    participant App as App Pod

    Device->>TSNet: Connect to Tailnet
    Note over TSNet: NAT traversal<br/>WireGuard encryption
    Device->>Device: DNS: argocd.int.jigga.xyz
    Note over Device: Cloudflare DNS returns<br/>192.168.7.230
    Device->>TSNet: Route to 192.168.7.230
    TSNet->>Router: Subnet route (192.168.7.224/29)
    Router->>Traefik: Forward to LB IP
    Traefik->>SVC: Host-based routing
    SVC->>App: Load balanced
    App-->>Device: Response via same path
```

**Flow Description:**
1. Device connects to Tailscale VPN
2. DNS query: `argocd.int.jigga.xyz` resolves to 192.168.7.230 (Cloudflare)
3. Device routes 192.168.7.230 via Tailscale (advertised subnet)
4. k3s-router forwards to Traefik LoadBalancer
5. Traefik matches Host header, routes to argocd-server
6. Response returns via same path

### Inter-Node Communication via SDN

```mermaid
flowchart LR
    subgraph PVE1["pve-alpha (192.168.7.233)"]
        VM1[ichigo<br/>10.0.0.10]
        VTEP1[VXLAN VTEP]
    end

    subgraph PVE2["pve-beta (192.168.7.234)"]
        VM2[naruto<br/>10.0.0.11]
        VTEP2[VXLAN VTEP]
    end

    subgraph PVE3["pve-gamma (192.168.7.235)"]
        VM3[tanjiro<br/>10.0.0.12]
        VTEP3[VXLAN VTEP]
    end

    VM1 --> VTEP1
    VTEP1 <-->|VXLAN Tunnel| VTEP2
    VTEP2 <-->|VXLAN Tunnel| VTEP3
    VTEP1 <-->|VXLAN Tunnel| VTEP3
    VTEP2 --> VM2
    VTEP3 --> VM3
```

**Traffic Path:** VM sends packet to k3svnet bridge, VTEP encapsulates in VXLAN, physical network transports UDP packet, remote VTEP decapsulates, delivers to destination VM.

## DNS Configuration

### Cloudflare DNS Records

| Record | Type | Value | Proxied | Purpose |
|--------|------|-------|---------|---------|
| `jigga.xyz` | CNAME | `<tunnel-id>.cfargotunnel.com` | Yes | Homepage |
| `passwords.jigga.xyz` | CNAME | `<tunnel-id>.cfargotunnel.com` | Yes | Vaultwarden |
| `*.int.jigga.xyz` | A | `192.168.7.230` | No | Internal wildcard |

### DNS Resolution Flow

```mermaid
flowchart TB
    subgraph Public["Public Domains - Cloudflare Proxy"]
        PUB_REQ[passwords.jigga.xyz]
        PUB_CNAME[CNAME: tunnel-id.cfargotunnel.com]
        PUB_EDGE[Cloudflare Edge IPs<br/>Proxied, SSL terminated]

        PUB_REQ --> PUB_CNAME --> PUB_EDGE
    end

    subgraph Internal["Internal Domains - DNS-only"]
        INT_REQ[argocd.int.jigga.xyz]
        INT_A[Wildcard A: 192.168.7.230]
        INT_TRAEFIK[Direct to Traefik<br/>via Tailscale VPN]

        INT_REQ --> INT_A --> INT_TRAEFIK
    end
```

## MetalLB Configuration

### IP Pool

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.7.230-192.168.7.235
```

### Current Allocations

| IP | Service | Namespace |
|----|---------|-----------|
| 192.168.7.230 | traefik | kube-system |
| 192.168.7.231-235 | Available | - |

### L2 Advertisement

```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
    - default-pool
```

## Firewall Rules

### Required Ports (Home Network)

| Port | Protocol | Source | Destination | Purpose |
|------|----------|--------|-------------|---------|
| 6443 | TCP | 192.168.7.0/24 | K3s nodes | Kubernetes API |
| 51820 | UDP | Tailscale | K3s nodes | WireGuard |
| 80/443 | TCP | MetalLB Pool | Any | HTTP/HTTPS |

### Kubernetes Network Policies

Currently using default allow-all. Consider implementing:

```yaml
# Example: Restrict pod-to-pod traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

## Troubleshooting

### Check Network Connectivity

```bash
# Test DNS resolution
nslookup passwords.jigga.xyz
nslookup argocd.int.jigga.xyz

# Test Cloudflare tunnel
kubectl logs -n cloudflare -l app=cloudflared --tail=20

# Test Tailscale connectivity
kubectl get connector -n tailscale
kubectl logs -n tailscale -l app=operator --tail=20

# Test MetalLB
kubectl get svc -A | grep LoadBalancer
```

### Common Issues

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| Public site unreachable | cloudflared pod down | `kubectl rollout restart deployment/cloudflared -n cloudflare` |
| Internal site unreachable | Not on Tailscale | Connect to Tailscale VPN |
| 502 Bad Gateway | Backend service down | Check app pod status |
| Certificate error | cert-manager issue | Check cert-manager logs |

## Related Documentation

- [Architecture Overview](architecture-overview.md) - Infrastructure diagram
- [SDN Configuration](sdn-configuration.md) - VXLAN overlay details
- [Maintenance Guide](maintenance-guide.md) - Troubleshooting procedures
