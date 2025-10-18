# GNS3 Server Module - Variables

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "storage_pool" {
  description = "Libvirt storage pool name"
  type        = string
}

variable "management_network_id" {
  description = "ID of management network"
  type        = string
}

variable "management_subnet" {
  description = "Management subnet CIDR"
  type        = string
}

variable "server_ip" {
  description = "Static IP address for GNS3 server"
  type        = string
  default     = "10.100.0.10"
}

variable "vcpus" {
  description = "Number of vCPUs"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 20
}

variable "gns3_version" {
  description = "GNS3 version to install"
  type        = string
  default     = "2.2.*"
}

variable "web_port" {
  description = "Port for GNS3 web UI"
  type        = number
  default     = 3080
}

variable "api_port" {
  description = "Port for GNS3 REST API"
  type        = number
  default     = 3080
}

variable "cisco_images_path" {
  description = "Path to store Cisco IOS images on GNS3 server"
  type        = string
  default     = "/home/ubuntu/GNS3/images/cisco"
}

variable "ssh_public_key" {
  description = "SSH public key for access (leave empty to generate)"
  type        = string
  default     = ""
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key (if ssh_public_key is provided)"
  type        = string
  default     = ""
}

variable "upload_cisco_images" {
  description = "Whether to upload Cisco images from local machine"
  type        = bool
  default     = false
}

variable "local_cisco_images_path" {
  description = "Local path to Cisco images (if upload_cisco_images is true)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
