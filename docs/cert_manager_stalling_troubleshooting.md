# Cert-Manager Stalling Issues - Comprehensive Troubleshooting Guide

## Quick Diagnosis and Recovery

If your `site.yaml` playbook is stalling on cert-manager tasks, use these tools:

### 1. Real-time Diagnosis
```bash
# Run comprehensive diagnosis
./scripts/diagnose_cert_manager_stall.sh

# Monitor cert-manager deployment in real-time
./scripts/site_runner_with_monitoring.sh --monitor-only
```

### 2. Enhanced Site Deployment with Monitoring
```bash
# Use the enhanced runner instead of raw ansible-playbook
./scripts/site_runner_with_monitoring.sh

# Or with custom inventory
./scripts/site_runner_with_monitoring.sh -i your_inventory.txt
```

### 3. Emergency Recovery
```bash
# Attempt automatic recovery
./scripts/site_runner_with_monitoring.sh --recover-only

# If that fails, manual cleanup and restart
kubectl delete namespace cert-manager --force --grace-period=0
helm uninstall cert-manager -n cert-manager || true
# Then re-run site deployment
```

## Common Stalling Scenarios

### 1. Helm Installation Timeout
**Symptoms:**
- Ansible hangs on "Install cert-manager using Helm" task
- No error messages, just timeout after 2-15 minutes

**Diagnosis:**
```bash
# Check if Helm is actually installing
helm list -n cert-manager
kubectl get pods -n cert-manager -w

# Check for namespace creation
kubectl get namespace cert-manager
```

**Solutions:**
1. **Resource constraints**: Ensure cluster has enough CPU/memory
2. **Network issues**: Check connectivity to `charts.jetstack.io` and container registries
3. **Previous installation**: Clean up failed installations

### 2. Pod Image Pull Issues
**Symptoms:**
- Pods stuck in `ImagePullBackOff` or `ErrImagePull`
- Timeout during rollout status checks

**Diagnosis:**
```bash
kubectl describe pods -n cert-manager | grep -A5 "Events:"
kubectl get events -n cert-manager --field-selector type!=Normal
```

**Solutions:**
1. **Registry connectivity**: Test access to `quay.io` and `docker.io`
2. **Proxy configuration**: Configure HTTP_PROXY if needed
3. **Image pull policy**: Already set to `IfNotPresent` in our fixes

### 3. CRD Installation Hanging
**Symptoms:**
- Hangs on "Install cert-manager CRDs" task
- CRDs partially created

**Diagnosis:**
```bash
kubectl get crd | grep cert-manager
kubectl describe crd certificates.cert-manager.io
```

**Solutions:**
1. **API server overload**: Check cluster health
2. **RBAC issues**: Ensure proper cluster admin permissions
3. **Network timeouts**: Increase timeout values

### 4. Rollout Status Timeout
**Symptoms:**
- Helm installation succeeds but rollout status hangs
- Deployments created but pods not becoming ready

**Diagnosis:**
```bash
kubectl get deployments -n cert-manager -o wide
kubectl rollout status deployment/cert-manager -n cert-manager --timeout=60s
```

**Solutions:**
1. **Node scheduling**: Check node taints and tolerations
2. **Resource requests**: Already optimized in our configuration
3. **Security policies**: Check PSP/PSA restrictions

## Diagnostic Output Analysis

When you encounter stalling, capture this diagnostic output:

### Essential Information
```bash
# Cluster state
kubectl cluster-info
kubectl get nodes -o wide
kubectl top nodes  # if metrics-server available

# cert-manager specific
kubectl get namespace cert-manager
helm list -n cert-manager
kubectl get pods -n cert-manager -o wide
kubectl get deployments -n cert-manager -o wide
kubectl get events -n cert-manager --sort-by=.metadata.creationTimestamp

# Network connectivity
curl -I https://charts.jetstack.io/index.yaml
curl -I https://registry-1.docker.io/v2/
curl -I https://quay.io/v2/
```

### Analysis Patterns

**1. Network Issues:**
```
dial tcp 104.16.182.7:443: i/o timeout
connection refused
no such host
```

**2. Resource Constraints:**
```
Insufficient cpu
Insufficient memory
0/3 nodes are available
```

**3. Image Pull Problems:**
```
ImagePullBackOff
ErrImagePull
manifest unknown
```

**4. RBAC Issues:**
```
forbidden: User "system:serviceaccount
admission webhook
```

## Site.yaml Integration Fixes

The enhanced monitoring system provides:

### Automatic Detection
- **Progress tracking**: Monitors cert-manager deployment phases
- **Stall detection**: Identifies when deployment stops progressing
- **Failure analysis**: Captures detailed diagnostic information

### Recovery Mechanisms
- **Automatic cleanup**: Removes failed installations
- **Retry logic**: Attempts recovery with different configuration
- **Fallback mode**: Provides manual recovery instructions

### Monitoring Integration
- **Real-time status**: Shows deployment progress
- **Log aggregation**: Captures all diagnostic output
- **Failure indicators**: Creates files for external monitoring

## Prevention Strategies

### 1. Pre-flight Checks
```bash
# Always run checks before site.yaml
ansible-playbook -i ansible/inventory.txt ansible/subsites/01-checks.yaml

# Verify cluster health
kubectl get nodes
kubectl cluster-info dump | grep -i error
```

### 2. Resource Planning
```bash
# Check available resources
kubectl describe nodes | grep -A5 "Allocated resources"
kubectl top nodes
```

### 3. Network Validation
```bash
# Test registry connectivity from nodes
kubectl run network-test --image=curlimages/curl --rm -it -- \
  curl -I https://charts.jetstack.io/index.yaml
```

### 4. Incremental Deployment
```bash
# Deploy components individually for better control
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cert_manager.yaml
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_local_path_provisioner.yaml
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml
```

## When to Use Enhanced Tools

### Use `diagnose_cert_manager_stall.sh` when:
- cert-manager deployment has already failed
- You need detailed analysis of current state
- Troubleshooting after a timeout

### Use `site_runner_with_monitoring.sh` when:
- Starting a new site.yaml deployment
- You want real-time monitoring and automatic recovery
- Previous deployments have had cert-manager issues

### Use manual recovery when:
- Automatic tools don't resolve the issue
- You need custom configuration
- Debugging specific edge cases

## Support Information

If issues persist after using these tools:

1. **Capture full diagnostic output**: Run `diagnose_cert_manager_stall.sh`
2. **Save deployment logs**: Check `/tmp/site_deployment_*.log`
3. **Include cluster info**: Node specifications, network topology
4. **Document timeline**: When did stalling occur, how long it lasted

The enhanced monitoring and recovery tools should resolve most cert-manager stalling issues automatically or provide clear guidance for manual resolution.