# Provider requirements for this module
# Versions are managed in the root versions.tf

terraform {
  required_providers {
    kubernetes = {
      source                = "hashicorp/kubernetes"
      configuration_aliases = [kubernetes]
    }
    helm = {
      source                = "hashicorp/helm"
      configuration_aliases = [helm]
    }
    local = {
      source = "hashicorp/local"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}