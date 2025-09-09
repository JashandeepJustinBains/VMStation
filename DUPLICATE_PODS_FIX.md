# Kubernetes Duplicate Pods and Node Join Failure Fix

## Problem Summary

The VMStation deployment was experiencing:

1. **Duplicate system pods**: 2 kube-flannel pods and 2 coredns pods running instead of 1 each
2. **Node join failures**: Storage node (192.168.4.61) failing to join with errors:
   - `Port 10250 is in use`
   - `/etc/kubernetes/pki/ca.crt already exists`

## Root Cause Analysis

- **Duplicate pods**: Flannel CNI and CoreDNS were being installed/scaled multiple times without idempotency checks
- **Join failures**: Nodes had stale Kubernetes artifacts from previous cluster attempts but weren't properly reset

## Solution Implemented

### 1. Flannel CNI Idempotency Fix

**Before:**
```yaml
- name: "Install Flannel CNI"
  shell: kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

**After:**
```yaml
- name: "Check if Flannel CNI is already installed"
  shell: kubectl get namespace kube-flannel >/dev/null 2>&1
  register: flannel_exists
  failed_when: false

- name: "Install Flannel CNI"
  shell: kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
  when: flannel_exists.rc != 0
```

### 2. CoreDNS Replica Count Fix

Added task to ensure CoreDNS has exactly 1 replica:

```yaml
- name: "Ensure CoreDNS has correct replica count"
  shell: |
    current_replicas=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.replicas}')
    if [ "$current_replicas" != "1" ]; then
      kubectl scale deployment coredns -n kube-system --replicas=1
    fi
```

### 3. Node Cleanup and Reset Logic

Added comprehensive cleanup for nodes with stale cluster artifacts:

```yaml
- name: "Reset node if it has cluster artifacts but isn't properly joined"
  block:
    - name: "Stop kubelet service"
      systemd:
        name: kubelet
        state: stopped

    - name: "Reset kubeadm configuration"
      shell: kubeadm reset --force

    - name: "Clean up iptables rules"
      shell: iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X

    - name: "Remove CNI configuration"
      shell: rm -rf /etc/cni/net.d/* && rm -rf /var/lib/cni/

    - name: "Clean up kubelet data"
      shell: rm -rf /var/lib/kubelet/*
  when: 
    - cluster_artifacts.stat.exists
    - not kubelet_conf.stat.exists
```

### 4. Enhanced Join Retry Logic

Improved retry logic with cleanup and preflight error handling:

```yaml
- name: "Handle join failure with cleanup and retry"
  block:
    - name: "Reset node after failed join"
      shell: kubeadm reset --force

    - name: "Retry join after cleanup"
      shell: /tmp/kubeadm-join.sh --ignore-preflight-errors=Port-10250,FileAvailable--etc-kubernetes-pki-ca.crt
  when: join_result.rc != 0
```

## Expected Outcomes

After applying these fixes:

1. **Single Flannel pods**: Only one kube-flannel pod per node (DaemonSet behavior)
2. **Single CoreDNS pods**: Exactly 1 CoreDNS replica in the cluster
3. **Successful node joins**: All nodes should join successfully, including the previously failing storage node
4. **Clean cluster state**: No duplicate or stale pods

## Validation

Run the test script to verify fixes:

```bash
./test_duplicate_pods_fix.sh
```

After deployment, validate the cluster:

```bash
kubectl get pods --all-namespaces
kubectl get nodes
```

You should see:
- Only 1 coredns pod in kube-system namespace
- Only 1 kube-flannel pod per node in kube-flannel namespace
- All nodes in Ready status

## Files Modified

- `ansible/plays/setup-cluster.yaml` - Added idempotency and cleanup logic
- `test_duplicate_pods_fix.sh` - New validation script