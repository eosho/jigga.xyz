# Provider requirements for this module
# Versions are managed in the root versions.tf

terraform {
  required_providers {
    kubernetes = {
      source                = "hashicorp/kubernetes"
      configuration_aliases = [kubernetes]
    }
  }
}