# Proxmox SDN Configuration

**Navigation:** [Main README](../README.md) | [Documentation Index](README.md) | [Network Architecture](network-architecture.md)

Documentation for the Proxmox Software-Defined Networking (SDN) VXLAN overlay used for cluster-internal communication.

## Overview

The SDN provides a private overlay network for K3s node communication, isolating cluster traffic from the public LAN.

```mermaid
flowchart TB
    subgraph SDN["Proxmox SDN Architecture"]
        subgraph Zone["SDN Zone: k3szone (VXLAN, MTU: 1450)"]
            subgraph VNet["VNet: k3svnet - Subnet: 10.0.0.0/24 - Gateway: 10.0.0.1"]
                VM1[ichigo<br/>10.0.0.10]
                VM2[naruto<br/>10.0.0.11]
                VM3[tanjiro<br/>10.0.0.12]
            end
        end

        subgraph Transport["VXLAN Transport Layer"]
            PVE1[pve-alpha<br/>192.168.7.233]
            PVE2[pve-beta<br/>192.168.7.234]
            PVE3[pve-gamma<br/>192.168.7.235]
        end
    end

    VM1 --- VNet
    VM2 --- VNet
    VM3 --- VNet

    PVE1 <-->|VXLAN| PVE2
    PVE2 <-->|VXLAN| PVE3
    PVE1 <-->|VXLAN| PVE3
```

## Configuration

### Terraform Variables

```hcl
# terraform.tfvars
enable_sdn = true
sdn_zone_id    = "k3szone"
sdn_vnet_id    = "k3svnet"
sdn_vnet_alias = "K3s Cluster Overlay Network"
proxmox_node_ips = ["192.168.7.233", "192.168.7.234", "192.168.7.235"]

sdn_mtu            = 1450           # 50 bytes less than physical MTU
sdn_subnet_cidr    = "10.0.0.0/24"
sdn_subnet_gateway = "10.0.0.1"
```

### Terraform Module

The SDN is configured via `modules/proxmox/sdn/`:

```hcl
# modules/proxmox/sdn/main.tf
resource "proxmox_virtual_environment_sdn_zone" "vxlan_zone" {
  zone_id = var.zone_id
  type    = "vxlan"
  peers   = var.proxmox_node_ips
  mtu     = var.mtu
}

resource "proxmox_virtual_environment_sdn_vnet" "cluster_vnet" {
  vnet_id = var.vnet_id
  zone    = proxmox_virtual_environment_sdn_zone.vxlan_zone.zone_id
  alias   = var.vnet_alias
}

resource "proxmox_virtual_environment_sdn_subnet" "cluster_subnet" {
  vnet   = proxmox_virtual_environment_sdn_vnet.cluster_vnet.vnet_id
  cidr   = var.subnet_cidr
  gateway = var.subnet_gateway
}
```

## How VXLAN Works

### Encapsulation Process

```mermaid
flowchart TB
    subgraph Original["Original Frame from VM"]
        O1[Ethernet Header]
        O2[IP Header<br/>10.0.0.10 -> 10.0.0.11]
        O3[TCP/UDP Header]
        O4[Payload]

        O1 --- O2 --- O3 --- O4
    end

    subgraph Encapsulated["VXLAN Encapsulated Packet"]
        E1[Outer Ethernet]
        E2[Outer IP<br/>.233 -> .234]
        E3[Outer UDP<br/>:4789]
        E4[VXLAN Header<br/>VNI]
        E5[Inner Ethernet]
        E6[Original IP Packet]

        E1 --- E2 --- E3 --- E4 --- E5 --- E6
    end

    Original -->|VTEP Encapsulation| Encapsulated
```

**MTU Consideration:**
- Physical MTU: 1500 bytes
- VXLAN overhead: ~50 bytes (outer headers)
- Inner MTU: 1450 bytes

### Traffic Flow Example

```mermaid
sequenceDiagram
    participant VM1 as ichigo (10.0.0.10)
    participant VTEP1 as VTEP on pve-alpha
    participant NET as Physical Network
    participant VTEP2 as VTEP on pve-beta
    participant VM2 as naruto (10.0.0.11)

    VM1->>VTEP1: Packet to 10.0.0.11
    Note over VTEP1: ARP lookup<br/>Encapsulate in VXLAN
    VTEP1->>NET: UDP packet<br/>.233 -> .234:4789
    NET->>VTEP2: Standard IP routing
    Note over VTEP2: Decapsulate VXLAN<br/>Extract original frame
    VTEP2->>VM2: Deliver to VM
```

## VM Network Configuration

### Dual-NIC Setup

Each K3s VM has two network interfaces:

| Interface | Bridge | Network | Purpose |
|-----------|--------|---------|---------|
| eth0 | vmbr0 | 192.168.7.0/24 | Public/LAN access |
| eth1 | k3svnet | 10.0.0.0/24 | Private/SDN |

### Cloud-Init Configuration

```yaml
# Configured via Terraform cloud-init
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 192.168.7.223/24
      gateway4: 192.168.7.1
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
    eth1:
      addresses:
        - 10.0.0.10/24
```

## Verification Commands

### On Proxmox Host

```bash
# Check SDN zone status
pvesh get /cluster/sdn/zones

# Check VNet configuration
pvesh get /cluster/sdn/vnets

# View VXLAN interfaces
ip -d link show | grep vxlan

# Check bridge status
brctl show | grep k3svnet

# Verify VXLAN peers
bridge fdb show dev vxlan_k3szone | grep dst
```

### On K3s Nodes

```bash
# Check network interfaces
ip addr show

# Verify SDN interface
ip addr show eth1

# Test inter-node connectivity (SDN)
ping -c 3 10.0.0.11  # From ichigo to naruto

# Check routing
ip route show
```

### Expected Output

```bash
# ip addr show eth1 (on ichigo)
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc fq_codel state UP
    inet 10.0.0.10/24 brd 10.0.0.255 scope global eth1

# ping 10.0.0.11
PING 10.0.0.11 (10.0.0.11) 56(84) bytes of data.
64 bytes from 10.0.0.11: icmp_seq=1 ttl=64 time=0.523 ms
```

## Troubleshooting

### SDN Not Working

```bash
# 1. Apply pending SDN changes
pvesh set /cluster/sdn

# 2. Restart networking on nodes
systemctl restart networking

# 3. Verify zone is active
pvesh get /cluster/sdn/zones/k3szone
```

### Common Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| No ARP responses | VXLAN not applied | Run `pvesh set /cluster/sdn` |
| MTU issues | Fragmentation | Ensure inner MTU is 1450 |
| One-way traffic | Asymmetric config | Check all node peer lists |
| Bridge missing | SDN not deployed | Verify VNet exists in Proxmox UI |

### Diagnostic Commands

```bash
# Check if VXLAN interface exists
ip link show | grep vxlan

# Verify bridge forwarding database
bridge fdb show | grep k3szone

# Check for packet drops
ip -s link show eth1

# Monitor VXLAN traffic
tcpdump -i vmbr0 port 4789
```

## Related Documentation

- [Network Architecture](network-architecture.md) - Complete network overview
- [Architecture Overview](architecture-overview.md) - Infrastructure diagram
- [Maintenance Guide](maintenance-guide.md) - Day-2 operations
