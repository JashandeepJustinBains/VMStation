# CCNA Practice Lab - Terraform Infrastructure

## 🎯 Overview

This Terraform configuration deploys a complete CCNA practice laboratory environment with Cisco routers, Ubuntu servers, and Windows Server VMs. The lab is **completely isolated** from your production VMStation network and provides real-time network topology visualization.

## ⚠️ Network Isolation

**This lab is fully isolated from production:**
- **Lab Network:** 10.100.0.0/16 (isolated)
- **Production Network:** 192.168.4.0/24 (no connectivity)
- **Management Access:** Only from homelab host (192.168.4.62)
- **Internet Access:** Optional via dedicated NAT (disabled by default)

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     CCNA Practice Lab Network                           │
│                     (10.100.0.0/16 - Isolated)                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐  │
│  │                  Cisco Router Network                           │  │
│  │                                                                  │  │
│  │  ┌──────────┐      ┌──────────┐      ┌──────────┐            │  │
│  │  │  Router1 │◄────►│  Router2 │◄────►│  Router3 │            │  │
│  │  │ c7200-S5 │      │ c7200-S5 │      │ c7200p-M │            │  │
│  │  │          │      │          │      │          │            │  │
│  │  │10.100.1.1│      │10.100.1.2│      │10.100.1.3│            │  │
│  │  └────┬─────┘      └────┬─────┘      └────┬─────┘            │  │
│  │       │                 │                 │                    │  │
│  └───────┼─────────────────┼─────────────────┼────────────────────┘  │
│          │                 │                 │                        │
│  ┌───────┴─────────────────┴─────────────────┴────────────────────┐  │
│  │                  Client Network Segment                         │  │
│  │                                                                  │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐      │  │
│  │  │ Ubuntu   │  │ Ubuntu   │  │  Windows │  │  Windows │      │  │
│  │  │ Server 1 │  │ Server 2 │  │ Server 1 │  │ Server 2 │      │  │
│  │  │10.100.2.1│  │10.100.2.2│  │10.100.2.3│  │10.100.2.4│      │  │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘      │  │
│  │                                                                  │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │              GNS3 Server & Visualization                         │  │
│  │                                                                  │  │
│  │  • Web UI: http://10.100.0.10:3080                             │  │
│  │  • REST API: http://10.100.0.10:3080/v3                        │  │
│  │  • Dynamips: Cisco router emulation                             │  │
│  │  • Real-time topology visualization                             │  │
│  │  • Link status monitoring                                        │  │
│  │                                                                  │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              │ SSH Management Only
                              │ (No routing to 192.168.4.0/24)
                              ▼
                     homelab (192.168.4.62)
                        RHEL10 Host
```

## 📦 Components

### 1. Cisco Routers (via Dynamips)
- **Router 1:** c7200-advipservicesk9-mz.152-4.S5
- **Router 2:** c7200-advipservicesk9-mz.152-4.S5
- **Router 3:** c7200p-advipsericesk9-mz.152-4.M

**Features:**
- Full IOS functionality for CCNA practice
- Console access via telnet
- Configurable interfaces and routing protocols
- VLAN support
- OSPF, EIGRP, BGP routing

### 2. Ubuntu Servers
- **Base:** Ubuntu 22.04 LTS or 24.04 LTS
- **Count:** Variable (default: 2)
- **Purpose:** Linux client devices, SSH/telnet practice
- **Configuration:** Cloud-init automated setup

### 3. Windows Servers
- **Base:** Windows Server 2022 Evaluation (180-day trial)
- **Count:** Variable (default: 2)
- **Purpose:** Windows client devices, RDP practice
- **Configuration:** Automated domain join (optional)

### 4. GNS3 Server
- **Purpose:** Network topology management and visualization
- **Web UI:** Real-time topology view with drag-and-drop
- **API:** REST API for automation and monitoring
- **Emulation:** Dynamips for Cisco IOS

## 🚀 Quick Start

### Prerequisites

1. **Homelab node must have:**
   - RHEL 10 installed
   - KVM/libvirt installed and enabled
   - Sufficient resources (see Resource Requirements)
   - SSH access from your workstation

2. **Required Cisco Images:**
   ```bash
   # Place your Cisco IOS images in:
   # /var/lib/libvirt/images/cisco/
   c7200-advipservicesk9-mz.152-4.S5.bin
   c7200p-advipsericesk9-mz.152-4.M.bin
   ```

3. **Terraform installed on your workstation:**
   ```bash
   # Windows (via Chocolatey)
   choco install terraform
   
   # Or download from https://www.terraform.io/downloads
   ```

### Deployment

```bash
# 1. Navigate to CCNA lab directory
cd f:\VMStation\terraform\ccna-lab\

# 2. Initialize Terraform
terraform init

# 3. Review the plan
terraform plan

# 4. Deploy the lab
terraform apply

# 5. Access GNS3 Web UI
# From homelab: http://10.100.0.10:3080
# Via SSH tunnel: ssh -L 3080:10.100.0.10:3080 root@192.168.4.62
# Then access: http://localhost:3080
```

### Accessing Cisco Routers

```bash
# SSH to homelab first
ssh root@192.168.4.62

# Connect to router console via telnet
telnet 10.100.1.1 5000  # Router 1
telnet 10.100.1.2 5000  # Router 2
telnet 10.100.1.3 5000  # Router 3

# Initial router config
Router> enable
Router# configure terminal
Router(config)# hostname R1
R1(config)# interface GigabitEthernet0/0
R1(config-if)# ip address 10.100.1.1 255.255.255.0
R1(config-if)# no shutdown
R1(config-if)# exit
R1(config)# end
R1# write memory
```

### Accessing VMs

```bash
# Ubuntu servers (SSH)
ssh ubuntu@10.100.2.1  # Ubuntu Server 1
ssh ubuntu@10.100.2.2  # Ubuntu Server 2

# Windows servers (RDP via SSH tunnel)
# From Windows workstation:
ssh -L 3389:10.100.2.3:3389 root@192.168.4.62
# Then RDP to localhost:3389
```

## 🔧 Configuration

### Custom VM Counts

Edit `terraform.tfvars`:

```hcl
ubuntu_vm_count = 4
windows_vm_count = 3
```

### Enable Internet Access (Optional)

By default, the lab has NO internet access. To enable:

```hcl
# In terraform.tfvars
enable_internet = true
```

This creates a NAT gateway for the lab network.

### Cisco IOS Image Paths

If your images are in a different location:

```hcl
# In terraform.tfvars
cisco_images_path = "/custom/path/to/images"
```

## 📊 Resource Requirements

### Minimum Specifications
- **CPU:** 8 cores
- **RAM:** 32 GB
- **Storage:** 200 GB free

### Recommended Specifications
- **CPU:** 16 cores (32 threads)
- **RAM:** 64 GB
- **Storage:** 500 GB SSD

### Resource Allocation per Component

| Component | vCPU | RAM | Storage |
|-----------|------|-----|---------|
| Router 1 (Dynamips) | 1 | 512 MB | 100 MB |
| Router 2 (Dynamips) | 1 | 512 MB | 100 MB |
| Router 3 (Dynamips) | 1 | 512 MB | 100 MB |
| Ubuntu Server (each) | 2 | 2 GB | 20 GB |
| Windows Server (each) | 2 | 4 GB | 60 GB |
| GNS3 Server | 2 | 4 GB | 20 GB |

**Total (default 2 Ubuntu + 2 Windows):**
- vCPU: 13 cores
- RAM: 21 GB
- Storage: 180 GB

## 🌐 Network Topology

### Subnets

| Subnet | Purpose | CIDR | DHCP Range |
|--------|---------|------|------------|
| Management | GNS3 Server | 10.100.0.0/24 | 10.100.0.10 |
| Routers | Cisco Router Interconnects | 10.100.1.0/24 | Static |
| Clients | Ubuntu/Windows VMs | 10.100.2.0/24 | 10.100.2.10-100 |
| Practice Subnet 1 | CCNA Lab Exercises | 10.100.10.0/24 | N/A |
| Practice Subnet 2 | CCNA Lab Exercises | 10.100.20.0/24 | N/A |
| Practice Subnet 3 | CCNA Lab Exercises | 10.100.30.0/24 | N/A |

### Router Connections

```
R1 (GigabitEthernet0/0) ◄──┐
                            │
R2 (GigabitEthernet0/0) ◄──┼── Shared Segment (10.100.1.0/24)
                            │
R3 (GigabitEthernet0/0) ◄──┘

R1 (GigabitEthernet0/1) ──► Client Network (10.100.2.0/24)
R2 (GigabitEthernet0/1) ──► Practice Subnet 1 (10.100.10.0/24)
R3 (GigabitEthernet0/1) ──► Practice Subnet 2 (10.100.20.0/24)
```

## 🔍 Network Visualization

### GNS3 Web UI

Access the GNS3 Web UI via SSH tunnel:

```bash
# From your Windows workstation
ssh -L 3080:10.100.0.10:3080 root@192.168.4.62

# Open browser to:
http://localhost:3080
```

**Features:**
- Real-time topology visualization
- Drag-and-drop interface editing
- Device console access
- Packet capture integration
- Link status monitoring (up/down)
- Bandwidth utilization graphs

### REST API

Query topology programmatically:

```bash
# Get all projects
curl http://localhost:3080/v3/projects

# Get project topology
curl http://localhost:3080/v3/projects/<project-id>/nodes

# Get link status
curl http://localhost:3080/v3/projects/<project-id>/links
```

### Custom Visualization Scripts

We provide custom Python scripts for topology monitoring:

```bash
# Install dependencies
pip install requests pyyaml

# Generate topology diagram
python3 scripts/generate-topology.py > topology.txt

# Monitor link status
python3 scripts/monitor-links.py

# Export topology as JSON
python3 scripts/export-topology.py > topology.json
```

## 🧪 CCNA Practice Scenarios

### Scenario 1: Basic Router Configuration
1. Connect to R1 console
2. Configure hostname and interfaces
3. Set up static routes to R2 and R3
4. Test connectivity with `ping`

### Scenario 2: Dynamic Routing (OSPF)
1. Configure OSPF on all three routers
2. Advertise connected networks
3. Verify routing tables
4. Test failover by disabling interfaces

### Scenario 3: VLANs and Inter-VLAN Routing
1. Create VLANs on R1
2. Configure trunk links between routers
3. Set up router-on-a-stick
4. Test VLAN isolation and routing

### Scenario 4: ACLs and Security
1. Create standard ACLs
2. Create extended ACLs
3. Apply ACLs to interfaces
4. Test traffic filtering

### Scenario 5: NAT Configuration
1. Configure NAT on R1
2. Set up PAT (Port Address Translation)
3. Test outbound connectivity
4. Verify NAT translations

## 🔐 Security Best Practices

1. **No Production Access:** Lab is isolated from 192.168.4.0/24
2. **Management Only:** Access only via homelab host SSH
3. **No Internet by Default:** Internet access disabled unless explicitly enabled
4. **Snapshot Before Changes:** Take libvirt snapshots before major config changes
5. **Regular Backups:** Backup router configs and VM states
6. **Strong Passwords:** Use strong passwords for all devices
7. **Firewall Rules:** Verify iptables/nftables rules on homelab host

## 🛠️ Troubleshooting

### Routers Not Starting

```bash
# Check Dynamips status
ssh root@192.168.4.62
systemctl status gns3-server

# Check router logs
journalctl -u gns3-server -f

# Verify Cisco images
ls -lh /var/lib/libvirt/images/cisco/
```

### Cannot Access GNS3 Web UI

```bash
# Verify GNS3 server is running
curl http://10.100.0.10:3080/v3/version

# Check SSH tunnel
ps aux | grep "ssh.*3080"

# Verify firewall on homelab
nft list ruleset | grep 3080
```

### VMs Not Getting IP Addresses

```bash
# Check libvirt network status
virsh net-list --all
virsh net-info ccna-lab-client-network

# Verify DHCP server
virsh net-dhcp-leases ccna-lab-client-network

# Check VM network interface
virsh domiflist ubuntu-server-1
```

### Network Isolation Broken

```bash
# Test from VM - should fail
ssh ubuntu@10.100.2.1
ping 192.168.4.63  # Should timeout

# Verify routing table
ip route show

# Check iptables rules
iptables -L -n -v | grep 10.100
```

## 🔄 Management Commands

### Terraform Operations

```bash
# View current state
terraform state list

# Show specific resource
terraform state show libvirt_domain.ubuntu_server[0]

# Destroy single resource
terraform destroy -target=libvirt_domain.windows_server[0]

# Destroy entire lab
terraform destroy

# Re-create lab
terraform apply
```

### Libvirt Operations

```bash
# List all VMs
virsh list --all

# Start VM
virsh start ubuntu-server-1

# Stop VM
virsh shutdown ubuntu-server-1

# Force stop VM
virsh destroy ubuntu-server-1

# Delete VM
virsh undefine ubuntu-server-1 --remove-all-storage

# Take snapshot
virsh snapshot-create-as ubuntu-server-1 clean-state

# Restore snapshot
virsh snapshot-revert ubuntu-server-1 clean-state

# List snapshots
virsh snapshot-list ubuntu-server-1
```

### GNS3 Operations

```bash
# Stop all routers
gns3ctl stop-project <project-id>

# Start all routers
gns3ctl start-project <project-id>

# Export project
gns3ctl export-project <project-id> > ccna-lab-backup.gns3project

# Import project
gns3ctl import-project ccna-lab-backup.gns3project
```

## 📚 Learning Resources

### CCNA Study Materials
- [Cisco CCNA Certification](https://www.cisco.com/c/en/us/training-events/training-certifications/certifications/associate/ccna.html)
- [Packet Tracer Practice Labs](https://www.netacad.com/courses/packet-tracer)
- [GNS3 Academy](https://academy.gns3.com/)
- [David Bombal YouTube Channel](https://www.youtube.com/c/DavidBombal)

### Cisco IOS Commands
- [Cisco IOS Command Reference](https://www.cisco.com/c/en/us/support/ios-nx-os-software/ios-15-0/products-command-reference-list.html)
- [CCNA Command Cheat Sheet](https://www.netwrix.com/cisco_commands_cheat_sheet.html)

### Network Simulation
- [GNS3 Documentation](https://docs.gns3.com/)
- [Dynamips Documentation](https://github.com/GNS3/dynamips)
- [Terraform Libvirt Provider](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs)

## 🗺️ Roadmap

### Phase 1: Core Infrastructure ✅
- [x] Terraform modules for routers and VMs
- [x] GNS3 server deployment
- [x] Network isolation
- [x] Basic visualization

### Phase 2: Enhanced Features (Planned)
- [ ] Automated CCNA lab scenarios
- [ ] Pre-configured topology templates
- [ ] Packet capture automation
- [ ] Performance monitoring dashboard
- [ ] Ansible playbooks for router config

### Phase 3: Advanced Features (Future)
- [ ] Multi-site WAN simulation
- [ ] SD-WAN lab scenarios
- [ ] Network automation with Python
- [ ] CI/CD integration for config testing
- [ ] Automated grading system

## 📝 File Structure

```
terraform/ccna-lab/
├── README.md                      # This file
├── main.tf                        # Main Terraform configuration
├── variables.tf                   # Input variables
├── outputs.tf                     # Output values
├── terraform.tfvars               # Variable values (user customizable)
├── provider.tf                    # Provider configuration
├── modules/
│   ├── networks/                  # Isolated network creation
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── gns3-server/              # GNS3 server deployment
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── cloud-init.yaml
│   ├── cisco-routers/            # Cisco router via Dynamips
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── router-config.j2
│   ├── ubuntu-vms/               # Ubuntu server VMs
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── cloud-init.yaml
│   └── windows-vms/              # Windows server VMs
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── autounattend.xml
├── scripts/
│   ├── setup-homelab.sh          # Prepare homelab node
│   ├── deploy-lab.sh             # Deploy CCNA lab
│   ├── destroy-lab.sh            # Destroy CCNA lab
│   ├── generate-topology.py      # Generate topology diagram
│   ├── monitor-links.py          # Monitor link status
│   ├── export-topology.py        # Export topology as JSON
│   └── test-isolation.sh         # Test network isolation
└── templates/
    ├── ccna-basic-lab.gns3       # Basic CCNA topology
    ├── ccna-routing-lab.gns3     # Routing protocols lab
    ├── ccna-switching-lab.gns3   # Switching and VLANs lab
    └── ccna-security-lab.gns3    # Security and ACLs lab
```

## 🤝 Contributing

Found an issue or want to add a feature? Please open an issue or pull request in the VMStation repository.

## 📄 License

This CCNA lab infrastructure is part of the VMStation project. See LICENSE in repository root.

---

**Status:** 🚧 In Development  
**Target Deployment:** homelab node (192.168.4.62)  
**Estimated Build Time:** 2-3 hours (initial setup)  
**Last Updated:** January 2025
