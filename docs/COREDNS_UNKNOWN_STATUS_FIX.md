# CoreDNS "Unknown" Status Fix

## Problem Description

After running `deploy.sh full` and regenerating flannel pods, CoreDNS pods may show "Unknown" status with no IP address assigned. This prevents DNS resolution in the cluster and causes other pods to remain stuck in "ContainerCreating" or "Pending" states.

## Symptoms

```bash
root@masternode:~# kubectl get pods -o wide --all-namespaces
NAMESPACE     NAME                          READY   STATUS    RESTARTS   AGE   IP        NODE
kube-system   coredns-76f75df574-jqcsw     0/1     Unknown   0          28h   <none>    masternode
```

Additional symptoms:
- Other pods stuck in "ContainerCreating" or "Pending" states
- DNS resolution fails within the cluster
- Flannel pods are running correctly (3/3 Ready)

## Root Cause

This issue typically occurs when:

1. **Flannel pods are regenerated** while CoreDNS pods are still scheduled on nodes
2. **Node taints** prevent CoreDNS from being rescheduled after flannel restart
3. **CNI configuration changes** leave existing pods in an inconsistent state
4. **Pod IP allocation fails** due to timing issues between flannel restart and CoreDNS scheduling

## Automated Fix

The VMStation deployment now includes automatic detection and fixing of this issue:

### During Deployment
```bash
./deploy.sh full
# Automatically detects and fixes CoreDNS issues after flannel setup
```

### Manual Fix
```bash
# Quick status check
./scripts/check_coredns_status.sh

# Apply comprehensive fix
./scripts/fix_coredns_unknown_status.sh
```

## What the Fix Does

### 1. Diagnosis Phase
- Checks CoreDNS pod status and IP assignment
- Analyzes node taints and CNI readiness
- Identifies flannel pod status on each node
- Reviews recent events and pod conditions

### 2. Fix Phase
- **Removes control-plane taints** that prevent CoreDNS scheduling
- **Adjusts CoreDNS replica count** based on cluster size
- **Deletes stuck CoreDNS pods** to force rescheduling
- **Waits for proper IP assignment** to new pods

### 3. Validation Phase
- **Tests DNS resolution** using a temporary test pod
- **Verifies all CoreDNS pods have IPs** and are running
- **Checks cluster-wide pod status** to ensure other pods can start

## Technical Details

### Control-Plane Taint Removal
```bash
kubectl taint node masternode node-role.kubernetes.io/control-plane:NoSchedule-
kubectl taint node masternode node-role.kubernetes.io/master:NoSchedule-
```

### CoreDNS Replica Adjustment
```bash
# For single-node or small clusters
kubectl scale deployment coredns -n kube-system --replicas=1

# For larger clusters  
kubectl scale deployment coredns -n kube-system --replicas=2
```

### Force Pod Rescheduling
```bash
kubectl delete pod -n kube-system <coredns-pod> --force --grace-period=0
kubectl rollout status deployment/coredns -n kube-system
```

## Prevention

The enhanced cluster setup now includes:

1. **Proactive taint removal** during cluster initialization
2. **Post-flannel CoreDNS validation** in the ansible playbook
3. **Automatic detection and remediation** in deploy.sh
4. **Improved timing** between flannel setup and CoreDNS scheduling

## Troubleshooting

If the automated fix doesn't resolve the issue:

### Check Flannel Status
```bash
kubectl get pods -n kube-flannel -o wide
kubectl logs -n kube-flannel -l app=flannel
```

### Check Node Conditions
```bash
kubectl get nodes -o wide
kubectl describe nodes
```

### Manual CoreDNS Restart
```bash
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system
```

### Check CNI Configuration
```bash
# On each node
ls -la /etc/cni/net.d/
cat /etc/cni/net.d/10-flannel.conflist
```

## Related Files

- `scripts/fix_coredns_unknown_status.sh` - Comprehensive fix script
- `scripts/check_coredns_status.sh` - Quick status checker
- `ansible/plays/setup-cluster.yaml` - Enhanced cluster setup with CoreDNS validation
- `deploy.sh` - Deployment script with automatic CoreDNS fix integration

## Success Indicators

After applying the fix, you should see:

```bash
# All CoreDNS pods running with IP addresses
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE
coredns-76f75df574-xyz123  1/1     Running   0          2m    10.244.0.10  masternode

# DNS resolution working
kubectl exec -n kube-system <test-pod> -- nslookup kubernetes.default.svc.cluster.local

# Other pods starting successfully
kubectl get pods --all-namespaces | grep -v "Running\|Completed"
# Should show minimal or no problematic pods
```

## Integration with VMStation

This fix is automatically integrated into the VMStation deployment process:

- **Cluster Setup**: ansible playbook includes CoreDNS validation
- **Full Deployment**: deploy.sh automatically runs CoreDNS check and fix
- **Manual Operations**: Scripts available for targeted troubleshooting

The fix ensures that after flannel regeneration, the entire cluster networking stack remains functional and all pods can schedule and run correctly.