# CCNA Lab - Provider Configuration

terraform {
  required_version = ">= 1.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
    
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    
    template = {
      source  = "hashicorp/template"
      version = "~> 2.2"
    }
  }
}

# Libvirt provider for KVM/QEMU management on homelab node
provider "libvirt" {
  uri = var.libvirt_uri
}
