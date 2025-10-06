# Robust Download Fix - Implementation Summary

## Problem Statement
CNI plugin downloads were failing with:
- **404 errors**: Hard-coded v1.6.1 URL no longer available
- **RHEL 10 urllib3 errors**: `HTTPSConnection.__init__() got an unexpected keyword argument 'cert_file'`
- **Architecture hard-coding**: Only amd64 supported, no arm64/other architectures
- **No fallback mechanism**: Single point of failure

## Solution Implemented

### Approach
**Hybrid Controller + Remote Fallback**: 
1. Controller attempts `get_url` with relaxed TLS validation
2. On failure (especially urllib3/cert_file errors), automatically falls back to `curl` on remote side
3. Architecture auto-detection ensures correct binary per host
4. Idempotent checks prevent unnecessary re-downloads

### Files Modified

#### 1. `ansible/playbooks/deploy-cluster.yaml` (Lines 42-95)
**Rationale**: Fix fragile CNI plugin downloads with architecture detection and robust fallback

**Changes**:
- Upgraded CNI plugins from v1.6.1 → v1.8.0 (verified available on GitHub)
- Added architecture detection: x86_64→amd64, aarch64→arm64
- Primary attempt with `get_url` (validate_certs: false)
- Automatic curl fallback when get_url fails with urllib3/cert_file errors
- Verification step to ensure download succeeded
- Cleanup of temporary archive after extraction

**Key improvements**:
- Works on RHEL 10 with urllib3 v2.x compatibility issues
- Supports mixed-architecture clusters
- Idempotent (won't re-download if loopback plugin exists)
- Deterministic error handling (fails fast with clear message)

#### 2. `ansible/plays/kubernetes/setup_helm.yaml` (Lines 25-51)
**Rationale**: Apply same robust download pattern to Helm installer script

**Changes**:
- Primary attempt with `get_url` (validate_certs: false, timeout: 30s)
- Automatic curl fallback on urllib3/cert_file errors
- Verification step to ensure script downloaded
- Fail fast with clear message if both methods fail

**Key improvements**:
- RHEL 10 compatible
- Network failure resilience
- Shorter timeout (30s vs default 60s) for faster failure detection

#### 3. `ansible/playbooks/verify-cni-downloads.yaml` (NEW)
**Rationale**: Provide verification playbook to validate CNI installation post-deployment

**Features**:
- Displays architecture mapping for each node
- Verifies /opt/cni/bin directory exists
- Lists all installed CNI plugins
- Checks for required plugins (loopback, bridge, host-local, portmap)
- Warns if temporary archives not cleaned up
- Summary output with next steps

#### 4. `.github/instructions/memory.instruction.md` (Appended)
**Rationale**: Document changes for future reference and continuity

**Added**: Changelog entry with summary of all improvements and file changes

## Verification Commands

### On Masternode (192.168.4.63)

#### 1. Syntax Check (Pre-deployment validation)
```bash
cd /root/VMStation
ansible-playbook --syntax-check ansible/playbooks/deploy-cluster.yaml
ansible-playbook --syntax-check ansible/plays/kubernetes/setup_helm.yaml
ansible-playbook --syntax-check ansible/playbooks/verify-cni-downloads.yaml
```
**Expected**: All 3 should return `playbook: <filename>` with exit code 0

#### 2. Dry-Run (Check mode - safe, no changes)
```bash
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/deploy-cluster.yaml --check
```
**Expected**: Shows what would change; may skip some tasks dependent on previous state

#### 3. Verify CNI Downloads (After deployment)
```bash
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/verify-cni-downloads.yaml
```
**Expected**:
- All nodes show correct architecture mapping
- CNI directory exists on all nodes
- Required plugins (loopback, bridge, host-local, portmap) present
- No temporary archives remaining
- Summary with "All nodes have been verified"

#### 4. Full Deployment Test
```bash
./deploy.sh
```
**Expected**:
- Phase 2 completes without CNI download errors
- No 404 errors
- No cert_file/urllib3 errors
- All nodes join cluster successfully

#### 5. Two-Cycle Idempotency Test
```bash
./deploy.sh reset
./deploy.sh
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/verify-cni-downloads.yaml
# Repeat
./deploy.sh reset
./deploy.sh
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/verify-cni-downloads.yaml
```
**Expected**:
- Both deployments succeed identically
- Second run shows "ok" for CNI tasks (already installed, skip download)
- Verification passes both times
- No errors, no changes on second verification

#### 6. Node Status Verification
```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system -o wide
kubectl get pods -n kube-flannel -o wide
```
**Expected**:
- All 3 nodes: Ready
- kube-proxy: 3/3 Running
- Flannel: 3/3 Running
- CoreDNS: 2/2 Running
- No CrashLoopBackOff

## Success Indicators

### During Deployment
- ✅ "Download CNI plugins (primary attempt)" completes OR
- ✅ "Download CNI plugins (curl fallback)" runs and completes
- ✅ "Verify CNI archive downloaded" passes
- ✅ "Extract CNI plugins" completes
- ✅ "Clean up CNI archive" removes temporary file

### After Deployment
- ✅ `/opt/cni/bin/loopback` exists on all nodes
- ✅ `/opt/cni/bin/bridge` exists on all nodes
- ✅ `/opt/cni/bin/host-local` exists on all nodes
- ✅ `/opt/cni/bin/portmap` exists on all nodes
- ✅ No `/tmp/cni-plugins.tgz` files remaining
- ✅ All nodes show Ready status
- ✅ Flannel pods Running on all nodes

### Idempotency Check
- ✅ Re-running deploy after successful deployment shows:
  - "Check if CNI plugins installed" → changed=0
  - "Download CNI plugins" → skipped (when condition not met)
  - No unnecessary downloads or extractions

## Technical Details

### Architecture Mapping
```yaml
ansible_architecture: x86_64  → cni_arch: amd64
ansible_architecture: aarch64 → cni_arch: arm64
ansible_architecture: armv7l  → cni_arch: arm  (pass-through)
```

### Fallback Trigger Conditions
Curl fallback activates when:
1. `get_url` task fails (register shows failed=true), OR
2. Error message contains "cert_file", OR
3. Error message contains "urllib3"

### Why This Approach?
- **No controller dependencies**: Doesn't require Ansible controller to have GitHub API access or special packages
- **Remote-side resilience**: curl is available on all nodes (installed by preflight/system-prep if needed)
- **No embedded tokens**: Uses public GitHub URLs, no authentication required
- **Standard tooling**: No custom scripts or helper utilities

### CNI Version Selection
- **v1.6.1**: Known to have 404 errors (assets removed or repository restructured)
- **v1.8.0**: Latest stable, verified available with all architecture variants
- **Alternatives considered**: v1.7.1, v1.6.0 (chose latest for long-term stability)

## Troubleshooting

### If CNI download still fails:

1. **Check network connectivity**:
```bash
ansible all -i ansible/inventory/hosts -m shell -a "curl -I https://github.com"
```

2. **Verify curl is installed**:
```bash
ansible all -i ansible/inventory/hosts -m shell -a "command -v curl || echo MISSING"
```

3. **Manual download test on failing node**:
```bash
ssh <node-ip>
curl -fsSL -o /tmp/test-cni.tgz \
  "https://github.com/containernetworking/plugins/releases/download/v1.8.0/cni-plugins-linux-amd64-v1.8.0.tgz"
ls -lh /tmp/test-cni.tgz
```

4. **Check GitHub API rate limits** (unlikely with public assets):
```bash
curl -s https://api.github.com/rate_limit
```

### If architecture detection fails:

Check Ansible facts:
```bash
ansible all -i ansible/inventory/hosts -m setup -a "filter=ansible_architecture"
```

Expected outputs:
- Debian/RHEL on x86_64: `ansible_architecture: x86_64`
- ARM64 systems: `ansible_architecture: aarch64`

## Maintenance

### Updating CNI Version
To update to a newer version (e.g., v1.9.0):

1. Verify assets exist:
```bash
curl -sL "https://github.com/containernetworking/plugins/releases/expanded_assets/v1.9.0" | \
  grep -o 'cni-plugins-linux-[^"]*\.tgz' | sort -u
```

2. Update version in `ansible/playbooks/deploy-cluster.yaml`:
```yaml
url: "https://github.com/containernetworking/plugins/releases/download/v1.9.0/cni-plugins-linux-{{ cni_arch }}-v1.9.0.tgz"
# Also update curl fallback URL
```

3. Test deployment on a single node first
4. Document version change in memory.instruction.md

---

**Last Updated**: 2025-10-04  
**Tested On**: Ansible core 2.14.18, Mixed Debian Bookworm + RHEL 10 cluster  
**Status**: Ready for deployment
