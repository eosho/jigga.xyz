# SDN Module - Provider Requirements
# This module uses the bpg/proxmox provider for SDN resources

terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}
