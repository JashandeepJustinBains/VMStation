# Deployment Guide

## Prerequisites

1. **Controller Machine** (masternode 192.168.4.63):
   - Ansible core 2.14.18+
   - Python 3.11+
   - SSH keys for all nodes

2. **Inventory Configuration**:
   - File: `ansible/inventory/hosts.yml`
   - Groups: `monitoring_nodes`, `storage_nodes`, `compute_nodes`
   - Edit host IPs and SSH settings as needed

3. **Vault Secrets** (for RHEL sudo password):
   ```bash
   ansible-vault create ansible/inventory/group_vars/secrets.yml
   ```
   
   Add:
   ```yaml
   vault_homelab_sudo_password: "your_sudo_password"
   ```

## Deployment Commands

### Deploy Debian Cluster Only
```bash
./deploy.sh debian
```

This runs:
- Phase 0: Install Kubernetes binaries (kubeadm, kubelet, kubectl)
- Phase 1: System preparation (sysctl, swap off, kernel modules)
- Phase 2: CNI plugins installation
- Phase 3: Control plane initialization (kubeadm init)
- Phase 4: Worker node join
- Phase 5: Flannel CNI deployment
- Phase 6: Wait for all nodes Ready
- Phase 7: Deploy monitoring stack and Jellyfin

### Deploy RKE2 on RHEL Only
```bash
./deploy.sh rke2
```

This runs:
- System preparation for RKE2
- RKE2 server installation
- Configuration and service start
- Monitoring components (node-exporter, Prometheus federation)
- Artifact collection (kubeconfig, logs)

### Deploy Everything
```bash
./deploy.sh all --with-rke2 --yes
```

Runs both Debian and RKE2 deployments in sequence.

### Reset All Clusters
```bash
./deploy.sh reset
```

Comprehensive cleanup:
- Drains all nodes
- Removes Kubernetes state (`/etc/kubernetes`, `/var/lib/kubelet`)
- Cleans CNI artifacts
- Resets iptables/nftables rules
- Uninstalls RKE2 from RHEL node

## Customization

### Change Kubernetes Version
Edit `ansible/inventory/hosts.yml`:
```yaml
all:
  vars:
    kubernetes_version: "1.29"  # Change to desired version
```

### Modify Pod/Service Networks
Edit `ansible/inventory/hosts.yml`:
```yaml
all:
  vars:
    pod_network_cidr: "10.244.0.0/16"     # Flannel default
    service_network_cidr: "10.96.0.0/12"   # Service CIDR
```

### Change CNI Plugin
Edit `ansible/inventory/hosts.yml`:
```yaml
all:
  vars:
    cni_plugin: flannel  # or calico
```

## Verification

After deployment, verify cluster health:

### Quick Validation (Recommended)
```bash
# Run complete validation suite
./tests/test-complete-validation.sh

# Or run specific validation tests
./tests/test-autosleep-wake-validation.sh      # Auto-sleep/wake configuration
./tests/test-monitoring-exporters-health.sh    # Monitoring stack health
./tests/test-monitoring-access.sh              # Monitoring endpoints
```

See [Validation Test Guide](docs/VALIDATION_TEST_GUIDE.md) for detailed documentation.

### Manual Verification

#### Debian Cluster
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A
```

Expected: All nodes `Ready`, all pods `Running`, no `CrashLoopBackOff`.

#### RKE2 Cluster
```bash
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
kubectl get pods -A
```

Expected: homelab node `Ready`, all system pods `Running`.

#### Monitoring Stack
```bash
# Access monitoring dashboards
open http://192.168.4.63:30300  # Grafana
open http://192.168.4.63:30090  # Prometheus

# Or test with curl
curl http://192.168.4.63:30300/api/health  # Should return "ok"
curl http://192.168.4.63:30090/-/healthy   # Should return "Prometheus is Healthy"
```

## Flags

| Flag | Description | Example |
|------|-------------|---------|
| `--yes` | Skip confirmations | `./deploy.sh all --yes` |
| `--check` | Dry-run mode | `./deploy.sh debian --check` |
| `--with-rke2` | Auto-proceed with RKE2 | `./deploy.sh all --with-rke2` |
| `--log-dir` | Custom log directory | `./deploy.sh debian --log-dir=/tmp/logs` |

## Troubleshooting Deployment

### Binaries Not Found
If `kubeadm: not found` appears:
- Binaries auto-install on next deployment
- OR manually install: `scripts/install-k8s-binaries-manual.sh` (if script exists)

### Sudo Password Errors (RHEL)
Ensure vault file exists:
```bash
ansible-vault view ansible/inventory/group_vars/secrets.yml
```

Re-run with:
```bash
./deploy.sh rke2 --ask-vault-pass
```

### Flannel Pods Not Ready
Check CNI config:
```bash
ssh root@192.168.4.63 "cat /etc/cni/net.d/10-flannel.conflist"
```

Should exist on all nodes. If missing, re-run deployment.

### Node Not Joining
Check join token validity:
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n kube-system get secrets | grep bootstrap-token
```

Reset and redeploy if token expired.

## Advanced: Manual Playbook Execution

Run specific playbooks directly:

```bash
cd ansible

# Deploy Debian cluster
ansible-playbook -i inventory/hosts.yml playbooks/deploy-cluster.yaml

# Deploy RKE2
ansible-playbook -i inventory/hosts.yml playbooks/install-rke2-homelab.yml --ask-vault-pass

# Reset everything
ansible-playbook -i inventory/hosts.yml playbooks/reset-cluster.yaml

# Verify cluster health
ansible-playbook -i inventory/hosts.yml playbooks/verify-cluster.yaml
```

## Idempotency Testing

Run deployment → reset → deployment cycles:
```bash
./tests/test-idempotence.sh
```

This validates the "100-times-in-a-row" requirement.
