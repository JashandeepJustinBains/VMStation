# VMStation Test Environment Setup and Validation Guide

## Overview

This guide provides comprehensive instructions for setting up and testing the VMStation Kubernetes cluster in a mixed OS environment with proper authentication handling.

## Test Environment Requirements

### Node Configuration

The VMStation cluster requires the following test environment:

| Node | OS | IP | User | Auth Method | Role |
|------|----|----|------|-------------|------|
| masternode | Debian Bookworm | 192.168.4.63 | root | SSH key | Control Plane + Monitoring |
| storagenodet3500 | Debian Bookworm | 192.168.4.61 | root | SSH key | Worker + Storage |
| homelab | RHEL 10 | 192.168.4.62 | jashandeepjustinbains | SSH key + sudo password | Worker + Compute |

### Key Differences

**Debian Nodes (masternode, storagenodet3500)**:
- Direct root access via SSH
- iptables-legacy backend
- No SELinux

**RHEL 10 Node (homelab)**:
- Non-root user `jashandeepjustinbains` with sudo
- Requires sudo password for privilege escalation
- nftables backend (iptables-nft)
- SELinux in permissive mode

## Pre-Deployment Setup

### 1. SSH Key Configuration

Ensure SSH keys are set up from masternode to all nodes:

```bash
# On masternode (192.168.4.63)
# Verify SSH connectivity
ssh root@192.168.4.61 hostname  # Should return: storagenodet3500
ssh jashandeepjustinbains@192.168.4.62 hostname  # Should return: homelab
```

### 2. Ansible Vault Setup for RHEL Sudo Password

Create encrypted secrets file for the RHEL sudo password:

```bash
# On masternode
cd /root/VMStation
ansible-vault create ansible/inventory/group_vars/secrets.yml
```

Add the following content (replace with actual password):

```yaml
---
# Sudo password for RHEL homelab node
vault_homelab_sudo_password: "YOUR_ACTUAL_SUDO_PASSWORD"

# Other secrets
grafana_admin_pass: "your_grafana_password"
```

### 3. Configure Group Variables

Create the actual group variables file from the template:

```bash
cp ansible/inventory/group_vars/all.yml.template ansible/inventory/group_vars/all.yml
```

Edit `ansible/inventory/group_vars/all.yml` and ensure it includes:

```yaml
# Reference the vaulted sudo password
ansible_become_pass: "{{ vault_homelab_sudo_password }}"
```

### 4. Verify Inventory Configuration

The inventory file at `ansible/inventory/hosts.yml` should already be configured with:

```yaml
compute_nodes:
  hosts:
    homelab:
      ansible_host: 192.168.4.62
      ansible_user: jashandeepjustinbains
      ansible_become: true
      ansible_become_method: sudo
```

## Running Tests

### Test 1: Environment Validation

Validate that all nodes are properly configured:

```bash
cd /root/VMStation
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/test-environment.yaml \
  --ask-vault-pass
```

**Expected Output:**
- ✅ All nodes ping successfully
- ✅ Authentication working on all nodes
- ✅ Sudo escalation works on homelab
- ✅ Root access works on Debian nodes
- ✅ Required packages detected (or warnings if missing)

### Test 2: Syntax Validation

Verify all playbooks have valid syntax:

```bash
cd /root/VMStation

# Check deployment playbook
ansible-playbook --syntax-check ansible/playbooks/deploy-cluster.yaml

# Check reset playbook  
ansible-playbook --syntax-check ansible/playbooks/reset-cluster.yaml

# Check verification playbook
ansible-playbook --syntax-check ansible/playbooks/verify-cluster.yaml
```

**Expected Output:**
```
playbook: ansible/playbooks/deploy-cluster.yaml
playbook: ansible/playbooks/reset-cluster.yaml
playbook: ansible/playbooks/verify-cluster.yaml
```

### Test 3: Single Deployment

Deploy the cluster once to verify basic functionality:

```bash
cd /root/VMStation
./deploy.sh
```

**Expected Results:**
- Deployment completes in 5-10 minutes
- No CrashLoopBackOff pods
- All nodes Ready
- All system pods Running

### Test 4: Deployment Verification

Verify the deployment is healthy:

```bash
cd /root/VMStation
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/verify-cluster.yaml \
  --ask-vault-pass
```

**Expected Output:**
- ✅ All nodes Ready
- ✅ Flannel DaemonSet ready
- ✅ kube-proxy pods Running
- ✅ CoreDNS pods Running
- ✅ CNI config present on all nodes
- ✅ No CrashLoopBackOff pods

### Test 5: Reset and Redeploy

Test that reset → deploy works correctly:

```bash
cd /root/VMStation

# Reset cluster
./deploy.sh reset
# Type 'yes' when prompted

# Deploy again
./deploy.sh

# Verify
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/verify-cluster.yaml \
  --ask-vault-pass
```

**Expected Results:**
- Reset completes in 2-3 minutes
- All Kubernetes config removed
- SSH access preserved
- Second deployment identical to first
- All verification checks pass

### Test 6: Idempotency Test (5 Cycles)

Test that deploy → reset → deploy works multiple times:

```bash
cd /root/VMStation
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/test-idempotency.yaml \
  --ask-vault-pass \
  -e "test_iterations=5"
```

**Expected Results:**
- All 5 cycles complete successfully
- Each deployment takes 5-10 minutes
- Each reset takes 2-3 minutes
- Total time: ~40-60 minutes
- No failures or errors

### Test 7: Extended Idempotency Test (100 Cycles)

For production validation, run the full 100-cycle test:

```bash
cd /root/VMStation

# Run in a screen/tmux session (takes ~20 hours)
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/test-idempotency.yaml \
  --ask-vault-pass \
  -e "test_iterations=100"
```

## Manual Verification Checks

After each deployment, manually verify:

### 1. Node Status
```bash
kubectl get nodes -o wide
```
Expected: All 3 nodes in Ready state

### 2. System Pods
```bash
kubectl get pods -n kube-system -o wide
kubectl get pods -n kube-flannel -o wide
```
Expected: All pods Running, no CrashLoopBackOff

### 3. Network Connectivity
```bash
# Test pod-to-pod communication
kubectl run test-pod --image=busybox --restart=Never --rm -it -- nslookup kubernetes.default
```
Expected: DNS resolution works

### 4. RHEL Node Specifics
```bash
# On homelab node
ssh jashandeepjustinbains@192.168.4.62

# Check CNI config
sudo cat /etc/cni/net.d/10-flannel.conflist

# Check Flannel interface
ip link show flannel.1

# Check nftables
sudo nft list ruleset | grep -A5 'table inet filter'

# Check SELinux
getenforce  # Should show: Permissive
```

### 5. Debian Node Specifics
```bash
# On masternode
cat /etc/cni/net.d/10-flannel.conflist
ip link show flannel.1
```

## Troubleshooting Common Issues

### Issue: Sudo password prompt on RHEL node

**Symptom:** Tasks fail on homelab with "missing sudo password"

**Solution:**
1. Ensure secrets.yml contains `vault_homelab_sudo_password`
2. Run playbooks with `--ask-vault-pass`
3. Verify inventory has `ansible_become: true` for homelab

### Issue: Flannel CrashLoopBackOff on RHEL

**Symptom:** Flannel pods crash on homelab node

**Solution:**
1. Check SELinux: `getenforce` should show Permissive
2. Check CNI config: `sudo cat /etc/cni/net.d/10-flannel.conflist`
3. Check nftables: network-fix role should configure permissive rules
4. Review Flannel logs: `kubectl logs -n kube-flannel <pod-name>`

### Issue: Nodes not becoming Ready

**Symptom:** Nodes stuck in NotReady state

**Solution:**
1. Check kubelet: `systemctl status kubelet`
2. Check CNI: Flannel pods must be Running first
3. Check network: `ip route` should show pod CIDR routes
4. Review logs: `journalctl -u kubelet -n 100`

### Issue: Timeout during deployment

**Symptom:** Deployment times out waiting for pods

**Solution:**
1. Check pod status: `kubectl get pods -A`
2. Check events: `kubectl get events -A --sort-by='.lastTimestamp'`
3. Verify network connectivity between nodes
4. Check container runtime: `systemctl status containerd`

## Performance Benchmarks

Expected deployment times on the test environment:

| Operation | Expected Time | Notes |
|-----------|---------------|-------|
| Fresh deployment | 5-10 minutes | Includes CNI setup and pod startup |
| Reset operation | 2-3 minutes | Includes cleanup and verification |
| Verification playbook | 1-2 minutes | Quick health checks |
| Single cycle (deploy+reset) | 7-13 minutes | Full cycle time |
| 5 cycles | 35-65 minutes | Idempotency test |
| 100 cycles | 12-22 hours | Production validation |

## Success Criteria

The environment is considered production-ready when:

- ✅ All 3 nodes join the cluster successfully
- ✅ All system pods (kube-proxy, CoreDNS, Flannel) are Running
- ✅ No CrashLoopBackOff or Error states
- ✅ CNI network functions correctly (pod-to-pod communication)
- ✅ DNS resolution works from pods
- ✅ Deploy → reset → deploy completes without errors
- ✅ 5-cycle idempotency test passes
- ✅ RHEL node with nftables works identically to Debian nodes
- ✅ Authentication (root on Debian, sudo on RHEL) works seamlessly

## Vault Password Management

### Creating Vault Password File (Optional)

For automated testing, create a vault password file:

```bash
# Create password file (NEVER commit this)
echo "your_vault_password" > ~/.vault_pass.txt
chmod 600 ~/.vault_pass.txt

# Use in playbooks
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/deploy-cluster.yaml \
  --vault-password-file ~/.vault_pass.txt
```

### Using Vault in CI/CD

For GitHub Actions or other CI/CD:

```yaml
- name: Deploy cluster
  env:
    ANSIBLE_VAULT_PASSWORD: ${{ secrets.ANSIBLE_VAULT_PASSWORD }}
  run: |
    echo "$ANSIBLE_VAULT_PASSWORD" > /tmp/vault_pass.txt
    ansible-playbook -i ansible/inventory/hosts.yml \
      ansible/playbooks/deploy-cluster.yaml \
      --vault-password-file /tmp/vault_pass.txt
    rm -f /tmp/vault_pass.txt
```

## Next Steps After Testing

Once all tests pass:

1. **Document your specific environment** - Record any customizations
2. **Set up monitoring** - Deploy the monitoring stack
3. **Configure backups** - Set up etcd backup procedures
4. **Plan maintenance windows** - Schedule cluster upgrades
5. **Implement auto-sleep** - Configure the idle sleep feature
6. **Add workloads** - Deploy Jellyfin and other applications

## Support and Debugging

If you encounter issues during testing:

1. Capture full output: `./deploy.sh 2>&1 | tee deploy.log`
2. Run diagnostics: `./scripts/smoke-test.sh`
3. Check memory.instruction.md for known issues
4. Review Output_for_Copilot.txt for requirements
5. Examine pod logs: `kubectl logs -n <namespace> <pod-name>`

## References

- Main deployment script: `./deploy.sh`
- Deployment playbook: `ansible/playbooks/deploy-cluster.yaml`
- Reset playbook: `ansible/playbooks/reset-cluster.yaml`
- Verification playbook: `ansible/playbooks/verify-cluster.yaml`
- Test environment playbook: `ansible/playbooks/test-environment.yaml`
- Idempotency test: `ansible/playbooks/test-idempotency.yaml`
- Network configuration: `ansible/roles/network-fix/tasks/main.yml`
- Flannel manifest: `manifests/cni/flannel.yaml`
