# CCNA Lab - Isolated Networks Module
# Creates completely isolated libvirt networks for CCNA practice

# ============================================================================
# Management Network (for GNS3 server)
# ============================================================================

resource "libvirt_network" "management" {
  name      = "${var.project_name}-management"
  mode      = "none"  # No forwarding - completely isolated
  domain    = "ccna.lab.internal"
  addresses = [var.management_subnet]
  
  autostart = true

  dhcp {
    enabled = true
  }

  dns {
    enabled    = true
    local_only = true
  }
}

# ============================================================================
# Router Interconnect Network
# ============================================================================

resource "libvirt_network" "routers" {
  name      = "${var.project_name}-routers"
  mode      = "none"  # No forwarding - completely isolated
  domain    = "routers.ccna.lab.internal"
  addresses = [var.router_subnet]
  
  autostart = true

  dhcp {
    enabled = false  # Routers use static IPs
  }

  dns {
    enabled    = true
    local_only = true
  }
}

# ============================================================================
# Client Network (Ubuntu and Windows VMs)
# ============================================================================

resource "libvirt_network" "clients" {
  name      = "${var.project_name}-clients"
  mode      = "none"  # No forwarding - completely isolated
  domain    = "clients.ccna.lab.internal"
  addresses = [var.client_subnet]
  
  autostart = true

  dhcp {
    enabled = true
  }

  dns {
    enabled    = true
    local_only = true
  }
}

# ============================================================================
# Practice Subnets (for CCNA exercises)
# ============================================================================

resource "libvirt_network" "practice" {
  count     = length(var.practice_subnets)
  
  name      = "${var.project_name}-practice-${count.index + 1}"
  mode      = "none"  # No forwarding - completely isolated
  domain    = "practice${count.index + 1}.ccna.lab.internal"
  addresses = [var.practice_subnets[count.index]]
  
  autostart = true

  dhcp {
    enabled = false  # Let students configure DHCP on routers
  }

  dns {
    enabled    = true
    local_only = true
  }
}

# ============================================================================
# Optional Internet Gateway (disabled by default)
# ============================================================================

resource "libvirt_network" "internet_gateway" {
  count = var.enable_internet ? 1 : 0
  
  name      = "${var.project_name}-internet"
  mode      = "nat"  # NAT mode for internet access
  domain    = "gateway.ccna.lab.internal"
  addresses = ["10.100.255.0/24"]
  
  autostart = true

  dhcp {
    enabled = true
  }

  dns {
    enabled    = true
    local_only = false  # Allow external DNS queries
  }
}

# ============================================================================
# Network Bridge for GNS3 (Optional)
# ============================================================================

# Note: GNS3 can use libvirt networks directly via macvtap
# This is handled in the GNS3 server module

# ============================================================================
# Firewall Rules on Homelab Host
# ============================================================================

# Deploy iptables/nftables rules to ensure isolation
resource "null_resource" "network_isolation_rules" {
  depends_on = [
    libvirt_network.management,
    libvirt_network.routers,
    libvirt_network.clients
  ]

  provisioner "remote-exec" {
    inline = [
      # Create isolation rules script
      "cat > /tmp/ccna-lab-isolation.sh << 'EOF'",
      "#!/bin/bash",
      "# CCNA Lab Network Isolation Rules",
      "",
      "# Get the production network interface",
      "PROD_IFACE=$(ip route | grep '192.168.4.0/24' | awk '{print $3}' | head -1)",
      "",
      "# Block traffic from CCNA lab networks to production network",
      "nft add table ip ccna_lab_isolation || true",
      "nft add chain ip ccna_lab_isolation forward { type filter hook forward priority 0 \\; } || true",
      "",
      "# Drop traffic from lab subnets to production subnet",
      "nft add rule ip ccna_lab_isolation forward ip saddr 10.100.0.0/16 ip daddr 192.168.4.0/24 counter drop",
      "",
      "# Log isolation violations (optional, for debugging)",
      "nft add rule ip ccna_lab_isolation forward ip saddr 10.100.0.0/16 ip daddr 192.168.4.0/24 log prefix \"CCNA-LAB-ISOLATION-BLOCK: \"",
      "",
      "# Allow lab-internal traffic",
      "nft add rule ip ccna_lab_isolation forward ip saddr 10.100.0.0/16 ip daddr 10.100.0.0/16 counter accept",
      "",
      "echo 'CCNA Lab network isolation rules applied'",
      "nft list table ip ccna_lab_isolation",
      "EOF",
      "",
      "chmod +x /tmp/ccna-lab-isolation.sh",
      "/tmp/ccna-lab-isolation.sh"
    ]

    connection {
      type     = "ssh"
      user     = "root"
      host     = var.homelab_ip
      timeout  = "2m"
    }
  }

  # Remove isolation rules on destroy
  provisioner "remote-exec" {
    when = destroy
    inline = [
      "nft delete table ip ccna_lab_isolation 2>/dev/null || true",
      "echo 'CCNA Lab network isolation rules removed'"
    ]

    connection {
      type     = "ssh"
      user     = "root"
      host     = var.homelab_ip
      timeout  = "2m"
    }
  }
}

# ============================================================================
# Network Status Check
# ============================================================================

resource "null_resource" "network_status" {
  depends_on = [
    libvirt_network.management,
    libvirt_network.routers,
    libvirt_network.clients,
    null_resource.network_isolation_rules
  ]

  provisioner "local-exec" {
    command = "echo 'CCNA Lab networks created and isolated successfully'"
  }

  provisioner "local-exec" {
    command = "echo 'Management Network: ${libvirt_network.management.name}'"
  }

  provisioner "local-exec" {
    command = "echo 'Router Network: ${libvirt_network.routers.name}'"
  }

  provisioner "local-exec" {
    command = "echo 'Client Network: ${libvirt_network.clients.name}'"
  }
}
