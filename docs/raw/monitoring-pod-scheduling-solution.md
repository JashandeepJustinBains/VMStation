# Monitoring Pod Scheduling and RKE2 Installation Fix

## Problem Statement

The deployment had two critical issues preventing successful cluster operation:

### Issue 1: Monitoring Pods (Prometheus and Grafana) Stuck in Pending State

**Error Message:**
```
0/2 nodes are available: 1 node(s) didn't match Pod's node affinity/selector, 
1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }
```

**Root Cause:**
- Prometheus and Grafana manifests had `nodeSelector` requiring control-plane nodes
- However, they lacked the necessary `tolerations` to schedule on control-plane nodes
- Control-plane nodes have a `node-role.kubernetes.io/control-plane:NoSchedule` taint by default
- Without proper tolerations, pods cannot be scheduled on tainted nodes

### Issue 2: RKE2 Installation Failure

**Error Message:**
```
HTTPSConnection.__init__() got an unexpected keyword argument 'cert_file'
```

**Root Cause:**
- The Ansible `get_url` module had SSL-related issues with deprecated parameters
- The module was failing to download the RKE2 installation script from https://get.rke2.io

## Solution

### Fix 1: Add Control-Plane Tolerations to Monitoring Stack

Modified both `manifests/monitoring/prometheus.yaml` and `manifests/monitoring/grafana.yaml` to include:

```yaml
tolerations:
- key: node-role.kubernetes.io/control-plane
  operator: Exists
  effect: NoSchedule
```

**Why this works:**
- The toleration allows pods to be scheduled on nodes with the control-plane taint
- Combined with the existing `nodeSelector`, ensures pods only run on control-plane nodes
- Follows the same pattern used by other critical system components (CoreDNS, kube-proxy)

### Fix 2: Replace get_url with shell/curl for RKE2 Download

Modified `ansible/playbooks/install-rke2-homelab.yml`:

**Before:**
```yaml
- name: "Download RKE2 installation script"
  get_url:
    url: https://get.rke2.io
    dest: /tmp/install-rke2.sh
    mode: '0755'
```

**After:**
```yaml
- name: "Download RKE2 installation script"
  shell: curl -sfL https://get.rke2.io -o /tmp/install-rke2.sh && chmod +x /tmp/install-rke2.sh
  args:
    creates: /tmp/install-rke2.sh
```

**Why this works:**
- Uses `curl` directly, avoiding Ansible module SSL parameter issues
- The `-sfL` flags provide: silent mode, fail on HTTP errors, follow redirects
- The `creates` argument ensures idempotency (won't re-download if file exists)

## Testing

Created two comprehensive test scripts:

### 1. `tests/test-monitoring-tolerations.sh`
Validates:
- Prometheus has control-plane toleration
- Prometheus has control-plane nodeSelector
- Grafana has control-plane toleration
- Grafana has control-plane nodeSelector

### 2. `tests/test-rke2-download.sh`
Validates:
- RKE2 playbook doesn't use problematic `get_url` module
- RKE2 playbook uses `shell/curl` method instead
- Curl command uses proper flags

Both test scripts pass successfully.

## Expected Behavior After Fix

### Monitoring Pods
- Prometheus and Grafana pods will successfully schedule on the control-plane node (masternode)
- Pods will transition from `Pending` to `Running` state
- Services will be accessible via NodePort (Prometheus:30090, Grafana:30300)

### RKE2 Installation
- RKE2 installation script will download successfully from https://get.rke2.io
- Installation will proceed without SSL-related errors
- Homelab node will be configured as an RKE2 server

## Verification Commands

After deployment, verify the fixes with:

```bash
# Check monitoring pods are running
kubectl get pods -n monitoring -o wide

# Verify pods are scheduled on control-plane
kubectl get pods -n monitoring -o json | jq '.items[].spec.nodeName'

# Check RKE2 installation on homelab
ssh jashandeepjustinbains@192.168.4.62 'sudo systemctl status rke2-server'
```

## Impact

### Minimal Changes
- **Modified:** 3 files (2 manifests, 1 playbook)
- **Added:** 2 test scripts
- **Total lines changed:** ~10 lines of actual configuration

### No Breaking Changes
- Existing deployments remain compatible
- Changes are additive (adding tolerations, switching download method)
- All existing functionality preserved

## References

Similar patterns used in:
- `manifests/network/coredns-deployment.yaml` (has control-plane tolerations)
- `manifests/cni/flannel.yaml` (has NoSchedule tolerations)
- Archive documentation: `archive/legacy-docs/old-docs/COREDNS_MASTERNODE_ENFORCEMENT.md`
