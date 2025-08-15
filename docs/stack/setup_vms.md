# VM Setup Guide

## Install KVM/Libvirt
```bash
sudo apt update && sudo apt install qemu-kvm libvirt-daemon-system virtinst -y
```

## Example Usage
```bash
virt-install --name myvm --ram 2048 --disk path=/var/lib/libvirt/images/myvm.img,size=20 --vcpus 2 --os-type linux --os-variant debian10 --network bridge=br0 --graphics none
```

## Tips
- Use Proxmox for advanced management
- Snapshot VMs before major changes
