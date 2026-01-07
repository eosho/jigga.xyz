# Proxmox Node Maintenance Guide

This guide covers the process for checking and applying updates to the Proxmox VE cluster nodes.

## Prerequisites

- Ansible installed (via WSL on Windows, or natively on Linux/macOS)
- SSH access to Proxmox nodes as root
- Access to the `ansible/` directory in this repository

## Inventory

The Proxmox nodes are defined in `ansible/inventory.yaml`:

| Node | IP Address |
|------|------------|
| pve-alpha | 192.168.7.233 |
| pve-beta | 192.168.7.234 |
| pve-gamma | 192.168.7.235 |

## Playbooks

### 1. Check for Updates (Safe/Read-Only)

Use this playbook to see what updates are available without making any changes.

```bash
cd ansible
ansible-playbook -i inventory.yaml playbooks/proxmox-check-updates.yaml
```

**What it does:**
- Refreshes the apt cache
- Lists all available updates
- Highlights security updates
- Shows if any node requires a reboot

**Example output:**
```
═══════════════════════════════════════════════════════
pve-alpha - Update Summary
═══════════════════════════════════════════════════════
Version: pve-manager/8.1.3/ec5affc9e41f1d79 (running kernel: 6.5.11-7-pve)
Updates available: 12
Security updates: 2
Reboot pending: ✓ No
═══════════════════════════════════════════════════════
```

### 2. Upgrade Nodes

⚠️ **WARNING**: This performs a full `dist-upgrade`. Always run the check playbook first!

#### Dry Run (Recommended First Step)

```bash
ansible-playbook -i inventory.yaml playbooks/proxmox-upgrade.yaml --check
```

#### Upgrade All Nodes (Parallel)

```bash
ansible-playbook -i inventory.yaml playbooks/proxmox-upgrade.yaml
```

#### Rolling Upgrade (One Node at a Time)

Recommended for production to maintain cluster availability:

```bash
ansible-playbook -i inventory.yaml playbooks/proxmox-upgrade.yaml -e "serial=1"
```

#### Upgrade with Automatic Reboot

If kernel updates are applied, a reboot may be required:

```bash
ansible-playbook -i inventory.yaml playbooks/proxmox-upgrade.yaml -e "reboot=true"
```

#### Rolling Upgrade with Reboot (Safest for Production)

```bash
ansible-playbook -i inventory.yaml playbooks/proxmox-upgrade.yaml -e "serial=1" -e "reboot=true"
```

#### Upgrade Specific Node Only

```bash
ansible-playbook -i inventory.yaml playbooks/proxmox-upgrade.yaml -l pve-alpha
```

## Maintenance Workflow

### Recommended Update Procedure

1. **Check cluster health** in Proxmox web UI
   - Verify all nodes are online
   - Check VM/container distribution
   - Review any existing alerts

2. **Check for available updates**
   ```bash
   ansible-playbook -i inventory.yaml playbooks/proxmox-check-updates.yaml
   ```

3. **Review the updates** - Pay attention to:
   - Kernel updates (will require reboot)
   - Proxmox VE package updates
   - Security updates

4. **Migrate VMs if needed** (for reboot scenarios)
   - Use Proxmox HA or manual migration to move critical VMs off the node being updated

5. **Perform rolling upgrade**
   ```bash
   ansible-playbook -i inventory.yaml playbooks/proxmox-upgrade.yaml -e "serial=1" -e "reboot=true"
   ```

6. **Verify cluster health** after completion
   - Check all nodes are online
   - Verify VMs/containers are running
   - Check Ceph health (if using Ceph storage)

### Emergency Single-Node Update

If you need to quickly update just one node:

```bash
# Check what's available
ansible-playbook -i inventory.yaml playbooks/proxmox-check-updates.yaml -l pve-alpha

# Apply updates
ansible-playbook -i inventory.yaml playbooks/proxmox-upgrade.yaml -l pve-alpha -e "reboot=true"
```

## Troubleshooting

### WSL "World Writable Directory" Warning

When running from WSL, you may see:
```
[WARNING]: Ansible is being run in a world writable directory...
```

**Solution**: Always specify the inventory explicitly with `-i inventory.yaml`

### SSH Connection Issues

If Ansible can't connect to nodes:

1. Verify SSH access manually:
   ```bash
   ssh root@192.168.7.233
   ```

2. Check SSH key is available:
   ```bash
   ls -la ~/.ssh/id_rsa
   ```

3. Ensure the node is reachable:
   ```bash
   ping 192.168.7.233
   ```

### Upgrade Fails Mid-Process

If an upgrade fails:

1. SSH directly to the affected node
2. Check apt status:
   ```bash
   dpkg --configure -a
   apt --fix-broken install
   ```
3. Re-run the upgrade playbook for that node

### Reboot Hangs

If a node doesn't come back after reboot:

1. Check physical/IPMI console access
2. Default reboot timeout is 600 seconds (10 minutes)
3. Verify network connectivity to the node

## Ceph Considerations

If using Ceph storage across the Proxmox cluster:

1. Check Ceph health before updates:
   ```bash
   ceph status
   ceph health detail
   ```

2. Set `noout` flag before rebooting nodes:
   ```bash
   ceph osd set noout
   ```

3. After all updates complete:
   ```bash
   ceph osd unset noout
   ceph status
   ```

## Scheduled Maintenance

Consider setting up a regular maintenance schedule:

- **Weekly**: Run `proxmox-check-updates.yaml` to review available updates
- **Monthly**: Apply non-critical updates during maintenance window
- **Immediately**: Apply critical security updates

## Related Documentation

- [Proxmox VE Admin Guide](https://pve.proxmox.com/pve-docs/pve-admin-guide.html)
- [Proxmox Package Repositories](https://pve.proxmox.com/wiki/Package_Repositories)
- [Cluster Manager](https://pve.proxmox.com/wiki/Cluster_Manager)
