# CCNA Lab - Terraform Outputs

# ============================================================================
# GNS3 Server Outputs
# ============================================================================

output "gns3_web_ui" {
  description = "GNS3 Web UI URL"
  value       = module.gns3_server.web_ui_url
}

output "gns3_api_url" {
  description = "GNS3 REST API URL"
  value       = module.gns3_server.api_url
}

output "gns3_ssh_command" {
  description = "SSH command to access GNS3 server"
  value       = module.gns3_server.ssh_command
}

output "gns3_server_ip" {
  description = "IP address of GNS3 server"
  value       = module.gns3_server.server_ip
}

# ============================================================================
# Network Outputs
# ============================================================================

output "management_network" {
  description = "Management network name"
  value       = module.networks.management_network_name
}

output "router_network" {
  description = "Router network name"
  value       = module.networks.router_network_name
}

output "client_network" {
  description = "Client network name"
  value       = module.networks.client_network_name
}

output "practice_networks" {
  description = "Practice network names"
  value       = module.networks.practice_network_names
}

output "network_isolation_status" {
  description = "Network isolation status"
  value       = "ENABLED - Lab network (10.100.0.0/16) isolated from production (192.168.4.0/24)"
}

# ============================================================================
# VM Outputs
# ============================================================================

output "ubuntu_vm_count" {
  description = "Number of Ubuntu VMs deployed"
  value       = var.ubuntu_vm_count
}

output "ubuntu_vm_names" {
  description = "Names of Ubuntu VMs"
  value       = libvirt_domain.ubuntu_vm[*].name
}

output "windows_vm_count" {
  description = "Number of Windows VMs to deploy"
  value       = var.windows_vm_count
}

# ============================================================================
# Resource Summary
# ============================================================================

output "total_vcpus_allocated" {
  description = "Total vCPUs allocated"
  value       = local.total_vcpus
}

output "total_memory_allocated_mb" {
  description = "Total memory allocated (MB)"
  value       = local.total_memory_mb
}

output "total_disk_allocated_gb" {
  description = "Total disk space allocated (GB)"
  value       = local.total_disk_gb
}

# ============================================================================
# Access Instructions
# ============================================================================

output "ssh_tunnel_command" {
  description = "SSH tunnel command to access GNS3 Web UI from local machine"
  value       = "ssh -L 3080:${module.gns3_server.server_ip}:${var.gns3_web_port} root@${var.homelab_ip}"
}

output "web_ui_access_url" {
  description = "URL to access GNS3 Web UI after SSH tunnel"
  value       = "http://localhost:3080 (after running SSH tunnel command)"
}

output "cisco_image_upload_command" {
  description = "SCP command to upload Cisco images"
  value       = "scp /path/to/cisco/*.bin ubuntu@${module.gns3_server.server_ip}:${module.gns3_server.cisco_images_path}/"
}

# ============================================================================
# Next Steps
# ============================================================================

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    
    CCNA Lab Deployed Successfully!
    
    1. Create SSH tunnel to access GNS3 Web UI:
       ${self.ssh_tunnel_command}
    
    2. Open browser to: http://localhost:3080
    
    3. Upload Cisco IOS images:
       scp /path/to/cisco/*.bin ubuntu@${module.gns3_server.server_ip}:${module.gns3_server.cisco_images_path}/
    
    4. In GNS3 Web UI:
       - Create/open project "${var.project_name}"
       - Add Dynamips routers with your IOS images
       - Configure network topology
       - Start routers and practice CCNA scenarios
    
    5. Access Ubuntu VMs:
       virsh -c ${var.libvirt_uri} net-dhcp-leases ${module.networks.client_network_name}
    
    For detailed instructions, see: DEPLOYMENT_INSTRUCTIONS.txt
  EOT
}
