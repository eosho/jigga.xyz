# Provider requirements for this module
# Versions are managed in the root versions.tf

terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
    local = {
      source = "hashicorp/local"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}