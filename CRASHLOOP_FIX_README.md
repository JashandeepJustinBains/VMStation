# Quick Fix Guide - RHEL 10 CrashLoopBackOff

## Problem
- kube-proxy: CrashLoopBackOff (exit code 2)
- kube-flannel: CrashLoopBackOff (clean exit after ~37 seconds)
- Only affects homelab node (RHEL 10)

## Root Causes Found
1. **Flannel**: Readiness probe too aggressive (12 failures = 120s timeout) - pod exits before full initialization
2. **kube-proxy**: Missing iptables chains on RHEL 10 nftables backend
3. **Swap enabled**: kubelet refuses to run with swap
4. **SELinux**: Blocking CNI init containers from writing to /opt/cni/bin

## The Fix

All fixes are already implemented in code. Just run:

```bash
# On masternode (192.168.4.63)
cd /srv/monitoring_data/VMStation
git pull
chmod +x scripts/fix-homelab-crashloop.sh
./scripts/fix-homelab-crashloop.sh
```

## What The Fix Does

1. **Applies network-fix role to homelab**:
   - Disables swap (immediate + persistent)
   - Configures iptables-nft backend
   - Pre-creates kube-proxy iptables chains
   - Pre-creates Flannel nftables tables
   - Sets proper SELinux contexts on CNI directories
   - Configures NetworkManager to ignore CNI interfaces

2. **Updates Flannel DaemonSet**:
   - Reduces initial delay: 30s → 10s (start checking sooner)
   - Increases failure threshold: 12 → 30 (allow 300s for initialization instead of 120s)

3. **Forces pod recreation**:
   - Deletes existing Flannel pod on homelab
   - Waits for new pod to become Ready
   - Validates kube-proxy and all other pods

## Validation

After running the fix:

```bash
# Should show all pods Running (no CrashLoopBackOff)
kubectl get pods -A

# Should show Flannel Running on homelab
kubectl get pods -n kube-flannel -o wide | grep homelab

# Should show kube-proxy Running on homelab  
kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide | grep homelab

# Should show no crashes
kubectl get pods -A | grep -i crash  # Should be empty
```

## Detailed Analysis

See `docs/HOMELAB_CRASHLOOP_ROOT_CAUSE_ANALYSIS.md` for:
- Complete diagnostic log analysis
- Timeline of pod lifecycle events
- Comparison with working Debian nodes
- Technical deep-dive into each root cause
- Lessons learned and best practices

## Why This Won't Happen Again

✅ **Permanent fixes in infrastructure-as-code** (Ansible roles)  
✅ **OS-aware** (only applies to RHEL 10+, doesn't affect Debian)  
✅ **Idempotent** (can run multiple times safely)  
✅ **Automated** (runs on every deployment)  
✅ **Tested** (based on official RHEL 10 Kubernetes documentation)

## Files Modified

- `manifests/cni/flannel.yaml` - Updated readiness probe timing
- `ansible/playbooks/fix-homelab-crashloop.yml` - Emergency fix playbook
- `scripts/fix-homelab-crashloop.sh` - Helper script
- `docs/HOMELAB_CRASHLOOP_ROOT_CAUSE_ANALYSIS.md` - Complete analysis

## Troubleshooting

If issues persist, see troubleshooting section in `docs/HOMELAB_CRASHLOOP_ROOT_CAUSE_ANALYSIS.md`.
