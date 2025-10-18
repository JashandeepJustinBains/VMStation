# CCNA Lab - Quick Start Guide

## Prerequisites

1. **Homelab node (192.168.4.62):**
   - RHEL 10 installed
   - SSH access configured
   - Minimum: 8 cores, 32GB RAM, 200GB disk
   
2. **Cisco IOS images:**
   - c7200-advipservicesk9-mz.152-4.S5.bin (x2)
   - c7200p-advipsericesk9-mz.152-4.M.bin (x1)
   
3. **Workstation:**
   - Terraform installed
   - SSH client (Windows: OpenSSH, PuTTY, or WSL)
   - Git Bash or WSL for scripts

## 5-Minute Deployment

### Step 1: Prepare Homelab (5 min)

```bash
# SSH to homelab
ssh root@192.168.4.62

# Install dependencies
dnf install -y qemu-kvm libvirt virt-install

# Enable libvirt
systemctl enable --now libvirtd

# Create directories
mkdir -p /var/lib/libvirt/images/{ccna-lab,cisco}
```

### Step 2: Upload Cisco Images (10 min)

```bash
# From your workstation
scp c7200*.bin root@192.168.4.62:/var/lib/libvirt/images/cisco/
```

### Step 3: Deploy with Terraform (15 min)

```bash
# On your workstation
cd f:\VMStation\terraform\ccna-lab

# Initialize
terraform init

# Deploy
terraform apply -auto-approve
```

### Step 4: Access GNS3 (2 min)

```bash
# Create SSH tunnel
ssh -L 3080:10.100.0.10:3080 root@192.168.4.62

# Open browser to:
# http://localhost:3080
```

### Step 5: Create Routers (10 min)

In GNS3 Web UI:

1. Click "New Project" or open "ccna-lab"
2. Drag Dynamips router template to canvas (x3)
3. Configure each router:
   - Right-click → Configure
   - Select your IOS image
   - Set RAM to 512MB
4. Connect routers:
   - Click cable icon
   - Connect Gi0/0 interfaces between routers
5. Start all routers (right-click → Start)
6. Open console (right-click → Console)

## Your First CCNA Scenario

### Basic Router Configuration

```cisco
! Router 1
Router> enable
Router# configure terminal
Router(config)# hostname R1
R1(config)# interface GigabitEthernet0/0
R1(config-if)# ip address 10.100.1.1 255.255.255.0
R1(config-if)# no shutdown
R1(config-if)# exit
R1(config)# end
R1# write memory

! Test connectivity
R1# ping 10.100.1.2
```

### Configure OSPF

```cisco
! On R1
R1(config)# router ospf 1
R1(config-router)# network 10.100.1.0 0.0.0.255 area 0
R1(config-router)# end
R1# write memory

! Verify
R1# show ip ospf neighbor
R1# show ip route ospf
```

## Verification Commands

```bash
# Check VMs
virsh -c qemu+ssh://root@192.168.4.62/system list --all

# Check networks
virsh -c qemu+ssh://root@192.168.4.62/system net-list

# Test isolation
./scripts/test-isolation.sh

# Monitor topology
python3 scripts/monitor-links.py
```

## Common Issues

**GNS3 not accessible:**
```bash
# Check service
ssh ubuntu@10.100.0.10
sudo systemctl status gns3server

# Restart if needed
sudo systemctl restart gns3server
```

**Router won't start:**
- Check IOS image is uploaded
- Verify RAM allocation (512MB minimum)
- Check homelab has enough resources

**Can't ping between routers:**
- Verify interfaces are "no shutdown"
- Check IP addresses are correct
- Verify cables are connected in GNS3

## Next Steps

1. Complete basic router configuration on all 3 routers
2. Configure dynamic routing (OSPF, EIGRP)
3. Practice VLANs and inter-VLAN routing
4. Implement ACLs and NAT
5. Try advanced scenarios from README.md

## Clean Up

```bash
# Destroy entire lab
cd f:\VMStation\terraform\ccna-lab
./scripts/destroy-lab.sh
```

## Support

- Full documentation: `README.md`
- Troubleshooting: See README.md "Troubleshooting" section
- GNS3 docs: https://docs.gns3.com/
- Cisco IOS commands: https://www.cisco.com/c/en/us/support/ios-nx-os-software/ios-15-0/products-command-reference-list.html

---

**Estimated time for complete setup: 45 minutes**
