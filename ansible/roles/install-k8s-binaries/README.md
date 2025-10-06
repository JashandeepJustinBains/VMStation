# install-k8s-binaries Role

## Purpose

This Ansible role installs Kubernetes binaries (kubeadm, kubelet, kubectl) and containerd on Debian and RHEL-based systems. It ensures all required components are present before cluster initialization.

## Features

- **Idempotent**: Checks if binaries already exist before attempting installation
- **Multi-OS Support**: Supports both Debian/Ubuntu and RHEL/CentOS systems
- **Version Pinning**: Installs Kubernetes v1.29 (stable) and holds packages to prevent accidental upgrades
- **Containerd Configuration**: Automatically configures containerd with SystemdCgroup enabled
- **Verification**: Validates installation by checking binary versions

## What It Installs

### On Debian/Ubuntu:
- apt prerequisites (curl, gnupg, etc.)
- Kubernetes apt repository (v1.29 stable)
- containerd
- kubeadm
- kubelet
- kubectl

### On RHEL/CentOS:
- Kubernetes yum repository (v1.29 stable)
- containerd
- kubeadm
- kubelet
- kubectl

## Usage

This role is automatically included in the `deploy-cluster.yaml` playbook as Phase 0, before system preparation and preflight checks.

```yaml
- name: Phase 0 - Install Kubernetes binaries
  hosts: monitoring_nodes:storage_nodes
  become: true
  gather_facts: true
  roles:
    - install-k8s-binaries
```

## Post-Reset Behavior

After running `./deploy.sh reset`, this role ensures that:
1. Missing binaries are automatically reinstalled
2. The cluster can be redeployed without manual intervention
3. Existing installations are not modified (idempotent)

## Requirements

- Ansible 2.9+
- Internet connectivity to download packages
- Root/sudo access on target nodes

## Variables

None. The role uses the Kubernetes v1.29 stable repository by default.

## Notes

- The role only runs on `monitoring_nodes` and `storage_nodes` groups (Debian)
- It does NOT run on `homelab` (which uses RKE2 instead of kubeadm)
- Package versions are held to prevent automatic upgrades
- SystemdCgroup is enabled in containerd for proper cgroup management
