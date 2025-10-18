# CCNA Lab - Main Terraform Configuration
# This is the main entry point that orchestrates all modules

# ============================================================================
# Storage Pool
# ============================================================================

resource "libvirt_pool" "ccna_lab" {
  name = var.storage_pool_name
  type = "dir"
  path = var.storage_pool_path
}

# ============================================================================
# Networks Module
# ============================================================================

module "networks" {
  source = "./modules/networks"

  project_name       = var.project_name
  homelab_ip         = var.homelab_ip
  management_subnet  = var.management_subnet
  router_subnet      = var.router_subnet
  client_subnet      = var.client_subnet
  practice_subnets   = var.practice_subnets
  enable_internet    = var.enable_internet
  tags               = var.tags
}

# ============================================================================
# GNS3 Server Module
# ============================================================================

module "gns3_server" {
  source = "./modules/gns3-server"

  depends_on = [module.networks]

  project_name           = var.project_name
  storage_pool           = libvirt_pool.ccna_lab.name
  management_network_id  = module.networks.management_network_id
  management_subnet      = var.management_subnet
  server_ip              = "10.100.0.10"
  vcpus                  = var.gns3_server_vcpus
  memory                 = var.gns3_server_memory
  disk_size              = var.gns3_server_disk_size
  web_port               = var.gns3_web_port
  api_port               = var.gns3_api_port
  cisco_images_path      = "/home/ubuntu/GNS3/images/cisco"
  ssh_public_key         = var.ubuntu_ssh_key
  tags                   = var.tags
}

# ============================================================================
# Cisco Routers via GNS3 REST API
# Note: Routers are managed via GNS3 API after server is deployed
# ============================================================================

# Create GNS3 project for CCNA lab
resource "null_resource" "create_gns3_project" {
  depends_on = [module.gns3_server]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Creating GNS3 project via REST API..."
      curl -X POST ${module.gns3_server.api_url}/projects \
        -H "Content-Type: application/json" \
        -d '{
          "name": "${var.project_name}",
          "auto_close": false,
          "auto_start": false,
          "auto_open": false
        }' > ${path.root}/.gns3_project.json
      
      echo "GNS3 project created"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "echo 'GNS3 project cleanup would happen here'"
  }
}

# ============================================================================
# Ubuntu VMs Module (to be created)
# ============================================================================

# Note: Ubuntu VMs module will be added in next iteration
# For now, we'll create basic Ubuntu VMs inline

resource "libvirt_volume" "ubuntu_base" {
  count  = var.ubuntu_vm_count > 0 ? 1 : 0
  name   = "${var.project_name}-ubuntu-base.qcow2"
  pool   = libvirt_pool.ccna_lab.name
  source = var.ubuntu_image_url
  format = "qcow2"
}

resource "libvirt_volume" "ubuntu_disk" {
  count          = var.ubuntu_vm_count
  name           = "${var.project_name}-ubuntu-${count.index + 1}.qcow2"
  pool           = libvirt_pool.ccna_lab.name
  base_volume_id = var.ubuntu_vm_count > 0 ? libvirt_volume.ubuntu_base[0].id : null
  size           = var.ubuntu_disk_size * 1024 * 1024 * 1024
  format         = "qcow2"
}

data "template_file" "ubuntu_cloud_init" {
  count    = var.ubuntu_vm_count
  template = file("${path.root}/templates/ubuntu-cloud-init.yaml")
  
  vars = {
    hostname = "${var.project_name}-ubuntu-${count.index + 1}"
    ssh_key  = var.ubuntu_ssh_key != "" ? var.ubuntu_ssh_key : ""
  }
}

resource "libvirt_cloudinit_disk" "ubuntu_init" {
  count     = var.ubuntu_vm_count
  name      = "${var.project_name}-ubuntu-${count.index + 1}-init.iso"
  pool      = libvirt_pool.ccna_lab.name
  user_data = data.template_file.ubuntu_cloud_init[count.index].rendered
}

resource "libvirt_domain" "ubuntu_vm" {
  count  = var.ubuntu_vm_count
  name   = "${var.project_name}-ubuntu-${count.index + 1}"
  memory = var.ubuntu_memory
  vcpu   = var.ubuntu_vcpus

  cloudinit = libvirt_cloudinit_disk.ubuntu_init[count.index].id

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.ubuntu_disk[count.index].id
  }

  network_interface {
    network_id     = module.networks.client_network_id
    hostname       = "${var.project_name}-ubuntu-${count.index + 1}"
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = true
  }

  autostart = false
}

# ============================================================================
# Windows VMs (Placeholder - Manual ISO deployment)
# ============================================================================

# Note: Windows VMs require ISO and autounattend.xml for automated setup
# This will be added in the windows-vms module

# ============================================================================
# Documentation and Instructions
# ============================================================================

resource "local_file" "deployment_instructions" {
  filename = "${path.root}/DEPLOYMENT_INSTRUCTIONS.txt"
  content  = <<-EOT
    CCNA Lab Deployment Complete!
    ==============================
    
    ## GNS3 Server
    - Web UI:  ${module.gns3_server.web_ui_url}
    - API:     ${module.gns3_server.api_url}
    - SSH:     ${module.gns3_server.ssh_command}
    
    ## Network Configuration
    - Management: ${var.management_subnet}
    - Routers:    ${var.router_subnet}
    - Clients:    ${var.client_subnet}
    
    ## Access Instructions
    
    1. Access GNS3 Web UI via SSH tunnel:
       ssh -L 3080:10.100.0.10:3080 root@${var.homelab_ip}
       Then open: http://localhost:3080
    
    2. Upload Cisco IOS images to GNS3 server:
       scp -i ${module.gns3_server.ssh_private_key_path} \
           /path/to/cisco/*.bin \
           ubuntu@10.100.0.10:/home/ubuntu/GNS3/images/cisco/
    
    3. Create routers in GNS3 Web UI:
       - Open the web UI
       - Create a new project or open "${var.project_name}"
       - Add Dynamips routers with your uploaded IOS images
       - Configure router interfaces and connections
       - Start the routers
    
    4. Access router consoles:
       - Via GNS3 Web UI (built-in console)
       - Or via telnet: telnet 10.100.0.10 <console-port>
    
    ## Ubuntu VMs Deployed
    - Count: ${var.ubuntu_vm_count}
    - Access: Check libvirt for IP assignments
      virsh -c ${var.libvirt_uri} net-dhcp-leases ${module.networks.client_network_name}
    
    ## Windows VMs
    - Count: ${var.windows_vm_count} (requires manual ISO setup)
    
    ## Network Isolation
    - Lab network (10.100.0.0/16) is ISOLATED from production (192.168.4.0/24)
    - Firewall rules enforced on homelab host
    - Test isolation: From any VM, try: ping 192.168.4.63 (should fail)
    
    ## Next Steps
    1. Upload your Cisco IOS images
    2. Create routers in GNS3
    3. Configure routing protocols
    4. Practice CCNA scenarios
    
    ## Useful Commands
    - List all VMs: virsh -c ${var.libvirt_uri} list --all
    - GNS3 status: ssh ubuntu@10.100.0.10 'systemctl status gns3server'
    - View logs: ssh ubuntu@10.100.0.10 'journalctl -u gns3server -f'
    
    For more information, see README.md
  EOT
}

# ============================================================================
# Resource Summary
# ============================================================================

resource "null_resource" "deployment_summary" {
  depends_on = [
    module.networks,
    module.gns3_server,
    libvirt_domain.ubuntu_vm,
    local_file.deployment_instructions
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo ""
      echo "╔═══════════════════════════════════════════════════════╗"
      echo "║     CCNA Lab Deployment Successful!                   ║"
      echo "╠═══════════════════════════════════════════════════════╣"
      echo "║                                                        ║"
      echo "║  GNS3 Web UI: ${module.gns3_server.web_ui_url}        "
      echo "║  REST API:    ${module.gns3_server.api_url}           "
      echo "║                                                        ║"
      echo "║  Ubuntu VMs:  ${var.ubuntu_vm_count}                  "
      echo "║  Windows VMs: ${var.windows_vm_count}                 "
      echo "║                                                        ║"
      echo "║  See DEPLOYMENT_INSTRUCTIONS.txt for next steps       ║"
      echo "║                                                        ║"
      echo "╚═══════════════════════════════════════════════════════╝"
      echo ""
    EOT
  }
}
