# Test Plan for Two-Phase Deployment

This document outlines how to test the new two-phase deployment system.

## Automated Tests

### Test 1: Verify --limit Behavior

Run the automated test suite:

```bash
./tests/test-deploy-limits.sh
```

**What it tests**:
- `debian` command uses `--limit monitoring_nodes,storage_nodes`
- `debian` command does NOT target homelab
- `rke2` command uses install-rke2-homelab.yml playbook
- `reset` command handles both Debian and RKE2 playbooks
- `all` command includes both phases

**Expected result**: All tests pass (4/4)

---

## Manual Dry-Run Tests

These tests verify the commands work correctly without actually deploying anything.

### Test 2: Debian Command Dry-Run

```bash
./deploy.sh debian --check
```

**Expected output**:
- Shows it would execute `ansible-playbook ... --limit monitoring_nodes,storage_nodes`
- Does NOT mention homelab
- Shows log location: `ansible/artifacts/deploy-debian.log`
- No actual deployment happens

### Test 3: RKE2 Command Dry-Run

```bash
./deploy.sh rke2 --check --yes
```

**Expected output**:
- Shows pre-flight checks (SSH, cleanup, Debian health)
- Shows it would execute `install-rke2-homelab.yml`
- Shows log location: `ansible/artifacts/install-rke2-homelab.log`
- No actual deployment happens

### Test 4: Reset Command Dry-Run

```bash
./deploy.sh reset --check --yes
```

**Expected output**:
- Shows it would execute reset-cluster.yaml (Debian)
- Shows it would execute uninstall-rke2-homelab.yml (homelab)
- No actual reset happens

### Test 5: All Command Dry-Run

```bash
./deploy.sh all --check --with-rke2
```

**Expected output**:
- Shows PHASE 1: Deploying to Debian Nodes
- Shows PHASE 2: Deploying RKE2 to Homelab
- No actual deployment happens

---

## Integration Tests (Requires Live Cluster)

⚠️ **Warning**: These tests make actual changes to the cluster. Only run in a test environment.

### Test 6: Full Deployment Flow

```bash
# Start from clean state
./deploy.sh reset --yes

# Deploy both phases
./deploy.sh all --with-rke2 --yes

# Verify Debian cluster
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
kubectl --kubeconfig=/etc/kubernetes/admin.conf get pods -A

# Verify RKE2 cluster
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
kubectl get pods -A
kubectl get pods -n monitoring-rke2
```

**Expected results**:
- Debian cluster: 2 nodes Ready (masternode, storagenodet3500)
- Debian pods: All Running in kube-system
- RKE2 cluster: 1 node Ready (homelab)
- RKE2 pods: node-exporter and prometheus Running in monitoring-rke2
- Logs exist in ansible/artifacts/

### Test 7: Phase-by-Phase Deployment

```bash
# Reset
./deploy.sh reset --yes

# Deploy Debian only
./deploy.sh debian --yes

# Verify Debian (wait 2-3 minutes for cluster to stabilize)
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
# Should show: masternode and storagenodet3500 Ready

# Deploy RKE2 only
./deploy.sh rke2 --yes

# Verify RKE2
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
# Should show: homelab Ready
```

**Expected results**:
- Each phase completes independently
- Logs exist for each phase
- Clusters are independent

### Test 8: Reset Both Clusters

```bash
# After deployment
./deploy.sh reset --yes

# Verify Debian cluster is gone
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes 2>&1
# Should fail (cluster not running)

# Verify RKE2 cluster is gone
ssh jashandeepjustinbains@192.168.4.62 "sudo systemctl status rke2-server"
# Should show inactive or not found
```

**Expected results**:
- Both clusters completely removed
- Network interfaces cleaned up
- Ready for fresh deployment

---

## Idempotency Tests

### Test 9: Re-run Debian Deployment

```bash
# Deploy Debian
./deploy.sh debian --yes

# Re-run immediately
./deploy.sh debian --yes

# Verify no errors, cluster still healthy
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
```

**Expected results**:
- Second run completes without errors
- Cluster remains healthy
- No duplicate resources created

### Test 10: Re-run RKE2 Deployment

```bash
# Deploy RKE2
./deploy.sh rke2 --yes

# Re-run immediately
./deploy.sh rke2 --yes

# Verify no errors, cluster still healthy
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
kubectl get pods -n monitoring-rke2
```

**Expected results**:
- Second run completes without errors
- Cluster remains healthy
- Monitoring pods still Running

---

## Error Handling Tests

### Test 11: RKE2 Without Debian Cluster

```bash
# Reset everything
./deploy.sh reset --yes

# Try to deploy RKE2 without Debian
./deploy.sh rke2 --yes
```

**Expected results**:
- Pre-flight check warns about Debian cluster not healthy
- Prompts for confirmation to continue
- RKE2 deploys but federation won't work until Debian is deployed

### Test 12: Invalid Command

```bash
./deploy.sh invalid-command
```

**Expected results**:
- Shows error message
- Displays usage/help
- Exits with non-zero status

### Test 13: Missing --with-rke2 Flag

```bash
./deploy.sh all
# Don't type 'y' at the prompt, just press Ctrl+C
```

**Expected results**:
- Prompts for confirmation before RKE2 deployment
- If not confirmed, deployment stops
- Use `--with-rke2` to skip confirmation

---

## Artifact Verification Tests

### Test 14: Check Log Files

```bash
# After deployment
ls -lh ansible/artifacts/

# Expected files:
# - deploy-debian.log
# - install-rke2-homelab.log
# - homelab-rke2-kubeconfig.yaml (if RKE2 deployed)
```

**Expected results**:
- All expected log files exist
- Logs contain deployment output
- Kubeconfig is valid YAML

### Test 15: Verify Kubeconfig Artifact

```bash
# Check kubeconfig exists
cat ansible/artifacts/homelab-rke2-kubeconfig.yaml

# Test it works
kubectl --kubeconfig=ansible/artifacts/homelab-rke2-kubeconfig.yaml get nodes
```

**Expected results**:
- Kubeconfig is valid
- Can access RKE2 cluster with it
- Shows homelab node

---

## Federation Tests

### Test 16: Test Monitoring Endpoints

```bash
# Node Exporter
curl http://192.168.4.62:9100/metrics | head

# Prometheus
curl http://192.168.4.62:30090/api/v1/status/config

# Federation endpoint
curl -s 'http://192.168.4.62:30090/federate?match[]={job=~".+"}' | head -20
```

**Expected results**:
- All endpoints return data
- Metrics are in Prometheus format
- Federation endpoint shows metrics from RKE2

---

## Performance Tests

### Test 17: Deployment Time

```bash
# Time full deployment
time ./deploy.sh all --with-rke2 --yes
```

**Expected duration**:
- Debian: 10-15 minutes
- RKE2: 15-20 minutes
- Total: 25-35 minutes

### Test 18: Reset Time

```bash
# Time reset
time ./deploy.sh reset --yes
```

**Expected duration**:
- 3-5 minutes total

---

## Test Results Template

Use this template to record test results:

```
Test Run: [DATE]
Operator: [NAME]
Environment: [PROD/TEST]

| Test # | Test Name | Status | Notes |
|--------|-----------|--------|-------|
| 1 | Automated limit tests | ☐ PASS ☐ FAIL | |
| 2 | Debian dry-run | ☐ PASS ☐ FAIL | |
| 3 | RKE2 dry-run | ☐ PASS ☐ FAIL | |
| 4 | Reset dry-run | ☐ PASS ☐ FAIL | |
| 5 | All dry-run | ☐ PASS ☐ FAIL | |
| 6 | Full deployment | ☐ PASS ☐ FAIL | Duration: ___ |
| 7 | Phase-by-phase | ☐ PASS ☐ FAIL | |
| 8 | Reset both | ☐ PASS ☐ FAIL | |
| 9 | Idempotent Debian | ☐ PASS ☐ FAIL | |
| 10 | Idempotent RKE2 | ☐ PASS ☐ FAIL | |
| 11 | RKE2 without Debian | ☐ PASS ☐ FAIL | |
| 12 | Invalid command | ☐ PASS ☐ FAIL | |
| 13 | Missing flag | ☐ PASS ☐ FAIL | |
| 14 | Log files | ☐ PASS ☐ FAIL | |
| 15 | Kubeconfig | ☐ PASS ☐ FAIL | |
| 16 | Federation | ☐ PASS ☐ FAIL | |
| 17 | Deploy time | ☐ PASS ☐ FAIL | Duration: ___ |
| 18 | Reset time | ☐ PASS ☐ FAIL | Duration: ___ |

Overall Result: ☐ ALL PASS ☐ SOME FAILED

Notes:
[Add any observations, issues, or recommendations]
```

---

## Acceptance Criteria

All tests should meet these criteria:

✅ **Automated tests**: 4/4 tests pass  
✅ **Dry-run tests**: All show correct behavior, no errors  
✅ **Deployment tests**: Both clusters deploy successfully  
✅ **Reset tests**: Both clusters fully removed  
✅ **Idempotency**: Re-running deployments works without errors  
✅ **Error handling**: Invalid commands fail gracefully  
✅ **Artifacts**: All logs and kubeconfigs created correctly  
✅ **Federation**: Monitoring endpoints accessible and working  
✅ **Performance**: Deployment completes in expected timeframe  

---

## Troubleshooting Test Failures

### Debian Deployment Fails

```bash
# Check logs
cat ansible/artifacts/deploy-debian.log | tail -50

# Common issues:
# - Network connectivity
# - Insufficient resources
# - Previous cluster not fully cleaned

# Fix: Reset and retry
./deploy.sh reset --yes
./deploy.sh debian --yes
```

### RKE2 Deployment Fails

```bash
# Check logs
cat ansible/artifacts/install-rke2-homelab.log | tail -50

# SSH to homelab
ssh jashandeepjustinbains@192.168.4.62
sudo journalctl -u rke2-server -n 100

# Common issues:
# - Old kubeadm artifacts
# - RKE2 download failed
# - Insufficient disk space

# Fix: Cleanup and retry
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/cleanup-homelab.yml
./deploy.sh rke2 --yes
```

### Federation Not Working

```bash
# Check if Prometheus is running
export KUBECONFIG=ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get pods -n monitoring-rke2

# Check if endpoints are accessible
curl http://192.168.4.62:9100/metrics
curl http://192.168.4.62:30090

# Common issues:
# - Firewall blocking ports
# - Pods not ready yet (wait 5 minutes)
# - Node IP changed
```

---

## CI/CD Integration

Example CI pipeline test stage:

```yaml
test:
  stage: test
  script:
    # Syntax check
    - bash -n deploy.sh
    
    # Automated tests
    - ./tests/test-deploy-limits.sh
    
    # Dry-run tests
    - ./deploy.sh debian --check
    - ./deploy.sh rke2 --check --yes
    - ./deploy.sh reset --check --yes
    - ./deploy.sh all --check --with-rke2
    
  artifacts:
    when: always
    paths:
      - ansible/artifacts/
```
