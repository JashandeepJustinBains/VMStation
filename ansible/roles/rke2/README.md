# RKE2 Ansible Role

This Ansible role installs and configures RKE2 (Rancher Kubernetes Engine 2) as a single-node Kubernetes control plane on RHEL-based systems.

## Purpose

Install a standalone RKE2 Kubernetes cluster on the RHEL 10 homelab node (192.168.4.62) to run an independent local Kubernetes control plane separate from the existing Debian-based cluster.

## Features

- ✅ Idempotent installation - safe to re-run
- ✅ Automatic system preparation (kernel modules, sysctl, swap disable)
- ✅ Configurable RKE2 version and CNI
- ✅ SELinux support for RHEL systems
- ✅ Automatic kubeconfig collection
- ✅ Comprehensive verification checks
- ✅ Installation logs collection

## Requirements

- RHEL 8, 9, or 10 based system
- Minimum 2GB RAM, 20GB disk space
- Root or sudo access
- Network connectivity for package downloads

## Role Variables

### Required Variables

None - all variables have sensible defaults.

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `rke2_version` | `v1.29.10+rke2r1` | RKE2 version to install |
| `rke2_channel` | `v1.29` | RKE2 release channel |
| `rke2_node_ip` | `{{ ansible_host }}` | Node IP address |
| `rke2_cluster_cidr` | `10.42.0.0/16` | Pod network CIDR |
| `rke2_service_cidr` | `10.43.0.0/16` | Service network CIDR |
| `rke2_cni` | `canal` | CNI plugin (canal, calico, cilium) |
| `rke2_kubeconfig_artifact_path` | `{{ playbook_dir }}/../artifacts/homelab-rke2-kubeconfig.yaml` | Where to save kubeconfig |

See `defaults/main.yml` for all available variables.

## Dependencies

None.

## Example Playbook

```yaml
---
- name: Install RKE2 on homelab
  hosts: homelab
  become: true
  roles:
    - role: rke2
      vars:
        rke2_version: "v1.29.10+rke2r1"
        rke2_cni: "canal"
```

## Usage

### 1. Prerequisites

Before running this role, clean up any existing Kubernetes installations:

```bash
# Run cleanup script on homelab node
ssh jashandeepjustinbains@192.168.4.62 'sudo /srv/monitoring_data/VMStation/scripts/cleanup-homelab-k8s-artifacts.sh'

# Or via Ansible playbook
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cleanup-homelab.yml
```

### 2. Install RKE2

```bash
# From repository root
cd /srv/monitoring_data/VMStation

# Run the installation playbook
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install-rke2-homelab.yml
```

### 3. Verify Installation

```bash
# Check kubeconfig was collected
ls -l ansible/artifacts/homelab-rke2-kubeconfig.yaml

# Use the kubeconfig to check cluster
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
kubectl get pods -A
```

## Post-Installation

### Accessing the Cluster

The kubeconfig file is saved to `ansible/artifacts/homelab-rke2-kubeconfig.yaml` with the server URL updated to use the node's IP address.

```bash
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
```

### Deploying Workloads

Deploy monitoring components and node-exporter using the manifests in `ansible/roles/rke2/files/`:

```bash
kubectl apply -f ansible/roles/rke2/files/monitoring-namespace.yaml
kubectl apply -f ansible/roles/rke2/files/node-exporter.yaml
kubectl apply -f ansible/roles/rke2/files/prometheus-federation.yaml
```

### Configuring Prometheus Federation

Add the following scrape configuration to your central Prometheus (on Debian control-plane):

```yaml
scrape_configs:
  - job_name: 'rke2-federation'
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job=~"kubernetes-.*"}'
        - '{job="node-exporter"}'
    static_configs:
      - targets:
          - '192.168.4.62:30090'
        labels:
          cluster: 'rke2-homelab'
```

## Verification Tests

The role includes built-in verification tasks that check:

- ✓ RKE2 binary installation
- ✓ Kubeconfig generation
- ✓ API server responsiveness
- ✓ Node Ready status
- ✓ Core system pods running
- ✓ Artifact collection

## Rollback / Uninstall

To remove RKE2:

```bash
# Via playbook
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/uninstall-rke2-homelab.yml

# Or manually on the node
sudo systemctl stop rke2-server
sudo /usr/local/bin/rke2-uninstall.sh
```

## Troubleshooting

### RKE2 service fails to start

Check logs:
```bash
sudo journalctl -u rke2-server -f
```

### Conflicting Kubernetes installation

Run the cleanup script:
```bash
sudo /srv/monitoring_data/VMStation/scripts/cleanup-homelab-k8s-artifacts.sh
```

### SELinux denials

Check audit logs:
```bash
sudo ausearch -m avc -ts recent
```

Set SELinux to permissive if needed:
```bash
sudo setenforce 0
```

### Network connectivity issues

Verify firewall rules allow required ports:
- 6443/tcp (Kubernetes API)
- 10250/tcp (Kubelet)
- 8472/udp (Flannel VXLAN)

## Files Structure

```
roles/rke2/
├── defaults/
│   └── main.yml          # Default variables
├── files/
│   ├── monitoring-namespace.yaml
│   ├── node-exporter.yaml
│   └── prometheus-federation.yaml
├── handlers/
│   └── main.yml          # Service handlers
├── meta/
│   └── main.yml          # Role metadata
├── tasks/
│   ├── main.yml          # Main task orchestration
│   ├── preflight.yml     # Pre-installation checks
│   ├── system-prep.yml   # System preparation
│   ├── install-rke2.yml  # RKE2 installation
│   ├── configure-rke2.yml # Configuration
│   ├── service.yml       # Service management
│   ├── verify.yml        # Verification
│   └── artifacts.yml     # Artifact collection
├── templates/
│   └── config.yaml.j2    # RKE2 config template
└── README.md            # This file
```

## License

MIT

## Author

Jashandeep Justin Bains - VMStation Project
