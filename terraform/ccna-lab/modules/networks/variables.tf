# Networks Module - Variables

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "homelab_ip" {
  description = "IP address of homelab node"
  type        = string
}

variable "management_subnet" {
  description = "Subnet for GNS3 server and management"
  type        = string
}

variable "router_subnet" {
  description = "Subnet for Cisco router interconnections"
  type        = string
}

variable "client_subnet" {
  description = "Subnet for Ubuntu and Windows VMs"
  type        = string
}

variable "practice_subnets" {
  description = "Additional subnets for CCNA practice exercises"
  type        = list(string)
}

variable "enable_internet" {
  description = "Enable internet access for lab network via NAT"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
