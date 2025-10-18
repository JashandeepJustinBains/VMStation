# CCNA Lab - Terraform Variables
# This file defines all configurable parameters for the CCNA practice lab

# ============================================================================
# Target Infrastructure
# ============================================================================

variable "libvirt_uri" {
  description = "Libvirt connection URI for homelab node"
  type        = string
  default     = "qemu+ssh://root@192.168.4.62/system"
}

variable "homelab_ip" {
  description = "IP address of homelab node"
  type        = string
  default     = "192.168.4.62"
}

# ============================================================================
# Network Configuration
# ============================================================================

variable "lab_network_cidr" {
  description = "CIDR block for entire CCNA lab network (isolated)"
  type        = string
  default     = "10.100.0.0/16"
}

variable "management_subnet" {
  description = "Subnet for GNS3 server and management"
  type        = string
  default     = "10.100.0.0/24"
}

variable "router_subnet" {
  description = "Subnet for Cisco router interconnections"
  type        = string
  default     = "10.100.1.0/24"
}

variable "client_subnet" {
  description = "Subnet for Ubuntu and Windows VMs"
  type        = string
  default     = "10.100.2.0/24"
}

variable "practice_subnets" {
  description = "Additional subnets for CCNA practice exercises"
  type        = list(string)
  default     = [
    "10.100.10.0/24",
    "10.100.20.0/24",
    "10.100.30.0/24"
  ]
}

variable "enable_internet" {
  description = "Enable internet access for lab network via NAT (disabled by default for isolation)"
  type        = bool
  default     = false
}

# ============================================================================
# Cisco Router Configuration
# ============================================================================

variable "cisco_images_path" {
  description = "Path to Cisco IOS images on homelab node"
  type        = string
  default     = "/var/lib/libvirt/images/cisco"
}

variable "cisco_router_configs" {
  description = "Configuration for Cisco routers"
  type = list(object({
    name        = string
    image       = string
    ram         = number
    nvram       = number
    console_port = number
    aux_port    = number
  }))
  default = [
    {
      name        = "R1"
      image       = "c7200-advipservicesk9-mz.152-4.S5.bin"
      ram         = 512
      nvram       = 256
      console_port = 5001
      aux_port    = 5101
    },
    {
      name        = "R2"
      image       = "c7200-advipservicesk9-mz.152-4.S5.bin"
      ram         = 512
      nvram       = 256
      console_port = 5002
      aux_port    = 5102
    },
    {
      name        = "R3"
      image       = "c7200p-advipsericesk9-mz.152-4.M.bin"
      ram         = 512
      nvram       = 256
      console_port = 5003
      aux_port    = 5103
    }
  ]
}

# ============================================================================
# GNS3 Server Configuration
# ============================================================================

variable "gns3_server_vcpus" {
  description = "Number of vCPUs for GNS3 server"
  type        = number
  default     = 2
}

variable "gns3_server_memory" {
  description = "Memory for GNS3 server (MB)"
  type        = number
  default     = 4096
}

variable "gns3_server_disk_size" {
  description = "Disk size for GNS3 server (GB)"
  type        = number
  default     = 20
}

variable "gns3_web_port" {
  description = "Port for GNS3 web UI"
  type        = number
  default     = 3080
}

variable "gns3_api_port" {
  description = "Port for GNS3 REST API"
  type        = number
  default     = 3080
}

# ============================================================================
# Ubuntu VM Configuration
# ============================================================================

variable "ubuntu_vm_count" {
  description = "Number of Ubuntu server VMs to deploy"
  type        = number
  default     = 2
}

variable "ubuntu_image_url" {
  description = "URL for Ubuntu cloud image"
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
}

variable "ubuntu_vcpus" {
  description = "Number of vCPUs per Ubuntu VM"
  type        = number
  default     = 2
}

variable "ubuntu_memory" {
  description = "Memory per Ubuntu VM (MB)"
  type        = number
  default     = 2048
}

variable "ubuntu_disk_size" {
  description = "Disk size per Ubuntu VM (GB)"
  type        = number
  default     = 20
}

variable "ubuntu_default_user" {
  description = "Default username for Ubuntu VMs"
  type        = string
  default     = "ubuntu"
}

variable "ubuntu_ssh_key" {
  description = "SSH public key for Ubuntu VMs (leave empty to generate)"
  type        = string
  default     = ""
}

# ============================================================================
# Windows Server Configuration
# ============================================================================

variable "windows_vm_count" {
  description = "Number of Windows Server VMs to deploy"
  type        = number
  default     = 2
}

variable "windows_image_path" {
  description = "Path to Windows Server ISO on homelab node"
  type        = string
  default     = "/var/lib/libvirt/images/windows/WindowsServer2022.iso"
}

variable "windows_vcpus" {
  description = "Number of vCPUs per Windows VM"
  type        = number
  default     = 2
}

variable "windows_memory" {
  description = "Memory per Windows VM (MB)"
  type        = number
  default     = 4096
}

variable "windows_disk_size" {
  description = "Disk size per Windows VM (GB)"
  type        = number
  default     = 60
}

variable "windows_admin_password" {
  description = "Administrator password for Windows VMs"
  type        = string
  sensitive   = true
  default     = "P@ssw0rd123!"
}

# ============================================================================
# Storage Configuration
# ============================================================================

variable "storage_pool_name" {
  description = "Libvirt storage pool name for CCNA lab"
  type        = string
  default     = "ccna-lab"
}

variable "storage_pool_path" {
  description = "Path for libvirt storage pool on homelab node"
  type        = string
  default     = "/var/lib/libvirt/images/ccna-lab"
}

# ============================================================================
# Project Configuration
# ============================================================================

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "ccna-lab"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {
    Project     = "VMStation"
    Component   = "CCNA-Lab"
    ManagedBy   = "Terraform"
    Environment = "Development"
    Isolated    = "true"
  }
}

# ============================================================================
# Visualization Configuration
# ============================================================================

variable "enable_grafana_dashboard" {
  description = "Enable Grafana dashboard for network monitoring"
  type        = bool
  default     = false
}

variable "enable_prometheus_exporter" {
  description = "Enable Prometheus exporter for GNS3 metrics"
  type        = bool
  default     = false
}

# ============================================================================
# Advanced Configuration
# ============================================================================

variable "enable_snapshots" {
  description = "Enable automatic snapshots before major changes"
  type        = bool
  default     = true
}

variable "snapshot_retention_days" {
  description = "Number of days to retain snapshots"
  type        = number
  default     = 7
}

variable "enable_packet_capture" {
  description = "Enable packet capture on all links"
  type        = bool
  default     = false
}

variable "packet_capture_path" {
  description = "Path for packet capture files"
  type        = string
  default     = "/var/lib/libvirt/images/ccna-lab/pcaps"
}

# ============================================================================
# Validation
# ============================================================================

locals {
  # Validate network configuration
  is_valid_network = (
    can(cidrhost(var.lab_network_cidr, 0)) &&
    can(cidrhost(var.management_subnet, 0)) &&
    can(cidrhost(var.router_subnet, 0)) &&
    can(cidrhost(var.client_subnet, 0))
  )

  # Validate VM counts
  is_valid_vm_count = (
    var.ubuntu_vm_count >= 0 &&
    var.ubuntu_vm_count <= 10 &&
    var.windows_vm_count >= 0 &&
    var.windows_vm_count <= 10
  )

  # Calculate total resource requirements
  total_vcpus = (
    length(var.cisco_router_configs) * 1 +
    var.gns3_server_vcpus +
    var.ubuntu_vm_count * var.ubuntu_vcpus +
    var.windows_vm_count * var.windows_vcpus
  )

  total_memory_mb = (
    sum([for r in var.cisco_router_configs : r.ram]) +
    var.gns3_server_memory +
    var.ubuntu_vm_count * var.ubuntu_memory +
    var.windows_vm_count * var.windows_memory
  )

  total_disk_gb = (
    1 +  # Cisco routers use minimal disk
    var.gns3_server_disk_size +
    var.ubuntu_vm_count * var.ubuntu_disk_size +
    var.windows_vm_count * var.windows_disk_size
  )
}

# Validation checks
resource "null_resource" "validate_configuration" {
  lifecycle {
    precondition {
      condition     = local.is_valid_network
      error_message = "Network configuration is invalid. Check CIDR blocks."
    }

    precondition {
      condition     = local.is_valid_vm_count
      error_message = "VM counts must be between 0 and 10."
    }

    precondition {
      condition     = local.total_vcpus <= 32
      error_message = "Total vCPU count (${local.total_vcpus}) exceeds recommended maximum of 32."
    }

    precondition {
      condition     = local.total_memory_mb <= 65536
      error_message = "Total memory (${local.total_memory_mb} MB) exceeds recommended maximum of 64 GB."
    }
  }
}
