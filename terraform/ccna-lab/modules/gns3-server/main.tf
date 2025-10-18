# GNS3 Server Module - Main Configuration
# Deploys GNS3 server VM for network topology management and visualization

# ============================================================================
# Ubuntu Cloud Image for GNS3 Server
# ============================================================================

resource "libvirt_volume" "gns3_base_image" {
  name   = "${var.project_name}-gns3-base.qcow2"
  pool   = var.storage_pool
  source = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
  format = "qcow2"
}

# ============================================================================
# GNS3 Server Root Disk
# ============================================================================

resource "libvirt_volume" "gns3_disk" {
  name           = "${var.project_name}-gns3-server.qcow2"
  pool           = var.storage_pool
  base_volume_id = libvirt_volume.gns3_base_image.id
  size           = var.disk_size * 1024 * 1024 * 1024  # Convert GB to bytes
  format         = "qcow2"
}

# ============================================================================
# Cloud-Init Configuration
# ============================================================================

data "template_file" "gns3_cloud_init_user_data" {
  template = file("${path.module}/cloud-init-user-data.yaml")
  
  vars = {
    hostname      = "${var.project_name}-gns3-server"
    ssh_key       = var.ssh_public_key != "" ? var.ssh_public_key : tls_private_key.gns3_ssh[0].public_key_openssh
    gns3_version  = var.gns3_version
    web_port      = var.web_port
    api_port      = var.api_port
    cisco_images_path = var.cisco_images_path
  }
}

data "template_file" "gns3_cloud_init_network_config" {
  template = file("${path.module}/cloud-init-network-config.yaml")
  
  vars = {
    ip_address = var.server_ip
    gateway    = cidrhost(var.management_subnet, 1)
    netmask    = cidrnetmask(var.management_subnet)
  }
}

resource "libvirt_cloudinit_disk" "gns3_init" {
  name           = "${var.project_name}-gns3-init.iso"
  pool           = var.storage_pool
  user_data      = data.template_file.gns3_cloud_init_user_data.rendered
  network_config = data.template_file.gns3_cloud_init_network_config.rendered
}

# ============================================================================
# SSH Key Generation (if not provided)
# ============================================================================

resource "tls_private_key" "gns3_ssh" {
  count     = var.ssh_public_key == "" ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "gns3_private_key" {
  count           = var.ssh_public_key == "" ? 1 : 0
  content         = tls_private_key.gns3_ssh[0].private_key_pem
  filename        = "${path.root}/.ssh/gns3_server_id_rsa"
  file_permission = "0600"
}

resource "local_file" "gns3_public_key" {
  count           = var.ssh_public_key == "" ? 1 : 0
  content         = tls_private_key.gns3_ssh[0].public_key_openssh
  filename        = "${path.root}/.ssh/gns3_server_id_rsa.pub"
  file_permission = "0644"
}

# ============================================================================
# GNS3 Server VM Domain
# ============================================================================

resource "libvirt_domain" "gns3_server" {
  name   = "${var.project_name}-gns3-server"
  memory = var.memory
  vcpu   = var.vcpus

  cloudinit = libvirt_cloudinit_disk.gns3_init.id

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.gns3_disk.id
  }

  network_interface {
    network_id     = var.management_network_id
    hostname       = "${var.project_name}-gns3-server"
    wait_for_lease = true
  }

  # Console access
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = true
  }

  # VM lifecycle
  autostart = true

  lifecycle {
    ignore_changes = [
      network_interface[0].addresses,
    ]
  }
}

# ============================================================================
# Wait for GNS3 Server to be Ready
# ============================================================================

resource "null_resource" "wait_for_gns3" {
  depends_on = [libvirt_domain.gns3_server]

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for GNS3 server to be ready...'",
      "timeout=300",
      "while [ $timeout -gt 0 ]; do",
      "  if systemctl is-active --quiet gns3server; then",
      "    echo 'GNS3 server is running'",
      "    exit 0",
      "  fi",
      "  echo 'Waiting for GNS3 server... ($timeout seconds left)'",
      "  sleep 10",
      "  timeout=$((timeout - 10))",
      "done",
      "echo 'ERROR: GNS3 server failed to start within timeout'",
      "systemctl status gns3server",
      "exit 1"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = var.server_ip
      private_key = var.ssh_public_key == "" ? tls_private_key.gns3_ssh[0].private_key_pem : file(var.ssh_private_key_path)
      timeout     = "10m"
    }
  }
}

# ============================================================================
# Configure GNS3 for Dynamips (Cisco Router Emulation)
# ============================================================================

resource "null_resource" "configure_dynamips" {
  depends_on = [null_resource.wait_for_gns3]

  provisioner "remote-exec" {
    inline = [
      "echo 'Configuring Dynamips for Cisco router emulation...'",
      
      # Install Dynamips
      "sudo apt-get update",
      "sudo apt-get install -y dynamips",
      
      # Create Cisco images directory
      "sudo mkdir -p ${var.cisco_images_path}",
      "sudo chown ubuntu:ubuntu ${var.cisco_images_path}",
      
      # Configure GNS3 server to use Dynamips
      "mkdir -p ~/.config/GNS3/2.2",
      "cat > ~/.config/GNS3/2.2/gns3_server.conf << 'EOF'",
      "[Server]",
      "host = 0.0.0.0",
      "port = ${var.api_port}",
      "images_path = ${var.cisco_images_path}",
      "projects_path = /home/ubuntu/GNS3/projects",
      "",
      "[Dynamips]",
      "allocate_aux_console_ports = True",
      "mmap_support = True",
      "sparse_memory_support = True",
      "ghost_ios_support = True",
      "EOF",
      
      # Restart GNS3 server
      "sudo systemctl restart gns3server",
      "sleep 5",
      
      "echo 'Dynamips configuration complete'"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = var.server_ip
      private_key = var.ssh_public_key == "" ? tls_private_key.gns3_ssh[0].private_key_pem : file(var.ssh_private_key_path)
      timeout     = "10m"
    }
  }
}

# ============================================================================
# Upload Cisco Images (if transfer enabled)
# ============================================================================

resource "null_resource" "upload_cisco_images" {
  count = var.upload_cisco_images ? 1 : 0

  depends_on = [null_resource.configure_dynamips]

  provisioner "file" {
    source      = var.local_cisco_images_path
    destination = var.cisco_images_path

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = var.server_ip
      private_key = var.ssh_public_key == "" ? tls_private_key.gns3_ssh[0].private_key_pem : file(var.ssh_private_key_path)
      timeout     = "30m"
    }
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Setting permissions on Cisco images...'",
      "chmod 644 ${var.cisco_images_path}/*.bin",
      "ls -lh ${var.cisco_images_path}/"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = var.server_ip
      private_key = var.ssh_public_key == "" ? tls_private_key.gns3_ssh[0].private_key_pem : file(var.ssh_private_key_path)
      timeout     = "5m"
    }
  }
}

# ============================================================================
# Health Check
# ============================================================================

resource "null_resource" "gns3_health_check" {
  depends_on = [null_resource.configure_dynamips]

  provisioner "local-exec" {
    command = "echo 'GNS3 server deployed successfully at http://${var.server_ip}:${var.web_port}'"
  }

  provisioner "local-exec" {
    command = "echo 'REST API available at http://${var.server_ip}:${var.api_port}/v3'"
  }

  provisioner "local-exec" {
    command = "echo 'SSH access: ssh -i ${var.ssh_public_key == "" ? "${path.root}/.ssh/gns3_server_id_rsa" : var.ssh_private_key_path} ubuntu@${var.server_ip}'"
  }
}
