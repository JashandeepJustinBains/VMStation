# Cluster Reset Enhancement - Validation Checklist

## Pre-Deployment Checks

- [ ] Pull latest changes to masternode
  ```bash
  cd /srv/monitoring_data/VMStation
  git fetch && git pull
  ```

- [ ] Verify new files exist
  ```bash
  ls -la ansible/roles/cluster-reset/tasks/main.yml
  ls -la ansible/playbooks/reset-cluster.yaml
  ls -la docs/CLUSTER_RESET_GUIDE.md
  ```

- [ ] Verify deploy.sh updated
  ```bash
  ./deploy.sh help | grep reset
  # Should show "reset" command
  ```

- [ ] Check inventory file
  ```bash
  ls -la ansible/inventory/hosts
  # Should exist (renamed from hosts.yml)
  ```

## Test 1: Dry Run

- [ ] Run reset in check mode
  ```bash
  ansible-playbook --check \
    -i ansible/inventory/hosts \
    ansible/playbooks/reset-cluster.yaml
  ```
  
- [ ] Verify no actual changes made
  ```bash
  kubectl get nodes
  # Should still show running cluster
  ```

## Test 2: Full Reset

- [ ] Run reset command
  ```bash
  ./deploy.sh reset
  ```

- [ ] Confirm when prompted (type 'yes')

- [ ] Watch for errors in output

- [ ] Verify completion message
  - Should show "CLUSTER RESET COMPLETED SUCCESSFULLY"

## Test 3: Post-Reset Validation

### On Control Plane (masternode - 192.168.4.63)

- [ ] No Kubernetes config
  ```bash
  ls /etc/kubernetes
  # Should not exist or be empty
  ```

- [ ] No K8s interfaces
  ```bash
  ip link show | grep -E 'flannel|cni|calico'
  # Should return nothing
  ```

- [ ] Kubelet stopped
  ```bash
  systemctl status kubelet
  # Should show "inactive (dead)"
  ```

- [ ] SSH keys preserved
  ```bash
  ls -la /root/.ssh/authorized_keys
  # Should exist with correct permissions
  ```

- [ ] Physical interface intact
  ```bash
  ip link show | grep -E 'eth|ens|eno|enp'
  # Should show your physical interface
  ```

### On Worker Nodes (storage and compute)

For each worker (192.168.4.61, 192.168.4.62):

- [ ] Test SSH connectivity
  ```bash
  ssh root@192.168.4.61 uptime
  ssh root@192.168.4.62 uptime
  ```

- [ ] No K8s config
  ```bash
  ssh root@192.168.4.61 'ls /etc/kubernetes'
  ssh root@192.168.4.62 'ls /etc/kubernetes'
  # Should not exist
  ```

- [ ] No K8s interfaces
  ```bash
  ssh root@192.168.4.61 'ip link | grep cni'
  ssh root@192.168.4.62 'ip link | grep cni'
  # Should return nothing
  ```

- [ ] Physical interfaces intact
  ```bash
  ssh root@192.168.4.61 'ip link | grep eth'
  ssh root@192.168.4.62 'ip link | grep eth'
  # Should show physical interface
  ```

## Test 4: Fresh Deployment

- [ ] Run deployment
  ```bash
  ./deploy.sh
  ```

- [ ] Watch for errors

- [ ] Verify completion

## Test 5: Post-Deploy Validation

- [ ] Nodes are Ready
  ```bash
  kubectl get nodes
  # All nodes should show "Ready"
  ```

- [ ] System pods running
  ```bash
  kubectl get pods -n kube-system
  # All pods should be Running
  ```

- [ ] Flannel pods running
  ```bash
  kubectl get pods -n kube-flannel
  # All flannel pods should be Running
  ```

- [ ] CoreDNS working
  ```bash
  kubectl run test --image=busybox --rm -it -- nslookup kubernetes.default
  # Should resolve
  ```

- [ ] Pod network working
  ```bash
  kubectl run test --image=busybox --rm -it -- ping 8.8.8.8
  # Should succeed
  ```

- [ ] Monitoring accessible
  ```bash
  curl -s http://192.168.4.63:30300 | grep -i grafana
  # Should return Grafana page
  ```

- [ ] Jellyfin accessible
  ```bash
  curl -s http://192.168.4.61:30096 | grep -i jellyfin
  # Should return Jellyfin page
  ```

## Test 6: Spin-down Workflow

- [ ] Test spin-down
  ```bash
  ./deploy.sh spindown
  ```

- [ ] Verify pods scaled down
  ```bash
  kubectl get deployments -A
  # Should show 0 replicas for most deployments
  ```

- [ ] Verify nodes cordoned
  ```bash
  kubectl get nodes
  # Should show "SchedulingDisabled"
  ```

## Test 7: Reset → Deploy Cycle

- [ ] Reset again
  ```bash
  ./deploy.sh reset
  ```

- [ ] Verify clean state (repeat Test 3 checks)

- [ ] Deploy again
  ```bash
  ./deploy.sh
  ```

- [ ] Verify cluster (repeat Test 5 checks)

## Test 8: Targeted Reset (Optional)

- [ ] Reset only workers
  ```bash
  ansible-playbook -i ansible/inventory/hosts \
    ansible/playbooks/reset-cluster.yaml \
    --limit compute_nodes:storage_nodes
  ```

- [ ] Verify workers reset, control plane intact
  ```bash
  ssh root@192.168.4.61 'ls /etc/kubernetes'  # Should not exist
  ls /etc/kubernetes  # Should still exist on masternode
  ```

## Test 9: Error Handling

- [ ] Run reset on already-reset cluster
  ```bash
  ./deploy.sh reset
  # Should complete without errors (idempotent)
  ```

- [ ] Cancel reset when prompted
  ```bash
  ./deploy.sh reset
  # Type 'no' when prompted
  # Should abort gracefully
  ```

## Test 10: Documentation Check

- [ ] Read docs
  ```bash
  less docs/CLUSTER_RESET_GUIDE.md
  less ansible/roles/cluster-reset/README.md
  less RESET_ENHANCEMENT_SUMMARY.md
  less QUICKSTART_RESET.md
  ```

- [ ] Verify accuracy
  - Commands work as documented
  - Explanations match behavior
  - Examples are correct

## Success Criteria

All checkboxes above should be checked ✅

### Critical Success Indicators:
1. Reset completes without SSH loss
2. Physical ethernet interfaces preserved
3. Clean deployment after reset works
4. All pods reach Running state
5. Network connectivity works (DNS, internet)
6. Services accessible (Grafana, Prometheus, Jellyfin)

### Known Acceptable Warnings:
- "Collection ansible.posix does not support Ansible version X" - OK
- "DEPRECATION WARNING: community.general.yaml" - OK
- kubeadm reset returns non-zero on nodes without kubeadm - OK (handled)

### Failure Indicators (Report if seen):
- SSH access lost after reset
- Physical interface removed
- Reset hangs indefinitely
- Deployment fails repeatedly after reset
- Kubernetes interfaces not cleaned

## Rollback Plan (If Issues Found)

```bash
# Restore from git
git fetch origin
git reset --hard origin/main

# If cluster is broken
# Manual kubeadm reset on each node:
ssh root@192.168.4.61 'kubeadm reset --force'
ssh root@192.168.4.62 'kubeadm reset --force'
kubeadm reset --force  # On masternode

# Redeploy
./deploy.sh
```

## Report Format

```
Test Results - Cluster Reset Enhancement
Date: YYYY-MM-DD
Tester: [Your Name]

Pre-Deployment: [ PASS / FAIL ]
Dry Run: [ PASS / FAIL ]
Full Reset: [ PASS / FAIL ]
Post-Reset Validation: [ PASS / FAIL ]
Fresh Deployment: [ PASS / FAIL ]
Post-Deploy Validation: [ PASS / FAIL ]
Spin-down Workflow: [ PASS / FAIL ]
Reset → Deploy Cycle: [ PASS / FAIL ]
Targeted Reset: [ PASS / FAIL / SKIPPED ]
Error Handling: [ PASS / FAIL ]

Overall: [ PASS / FAIL ]

Notes:
- [Any issues or observations]
- [Performance metrics if available]
- [Suggestions for improvement]
```

## Next Steps After Validation

If all tests pass:
1. ✅ Mark enhancement as complete
2. ✅ Update project README with reset info
3. ✅ Share QUICKSTART_RESET.md with team
4. ✅ Consider automation/CI integration

If tests fail:
1. Document failure details
2. Check logs: `journalctl -xe`
3. Review playbook output
4. Submit bug report with details
