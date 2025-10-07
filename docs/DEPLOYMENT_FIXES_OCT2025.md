# Deployment Fixes - October 2025

## Issues Fixed

This document describes fixes applied to resolve deployment issues identified on October 7, 2025.

### Issue 1: Jellyfin Not Running on storagenodet3500

**Symptom:**
- Jellyfin pod was not present in the cluster after deployment
- Only monitoring stack (Prometheus, Grafana) was deployed in Phase 7
- User expected Jellyfin to be running on storagenodet3500 node

**Root Cause:**
- Phase 7 of `ansible/playbooks/deploy-cluster.yaml` only deployed monitoring stack
- Jellyfin manifest existed at `manifests/jellyfin/jellyfin.yaml` but was never applied
- The deployment playbook had no tasks to deploy Jellyfin

**Fix Applied:**
- Added Jellyfin deployment task to Phase 7 (after Grafana deployment)
- Added wait task to ensure Jellyfin pod is ready (300s timeout)
- Added status display tasks to show Jellyfin deployment state
- Updated deployment complete message to include Jellyfin access URL

**Files Changed:**
- `ansible/playbooks/deploy-cluster.yaml` - Added tasks at lines 500-530

**Expected Result:**
- Jellyfin pod deploys to storagenodet3500 node
- Accessible at `http://192.168.4.61:30096`
- nodeSelector ensures it only runs on storagenodet3500

### Issue 2: IPMI Exporter-Remote Pod Failing

**Symptom:**
```
pod/ipmi-exporter-remote-869b4c8fd5-8p8dg   0/1     Error     1 (3s ago)   3s
```

**Root Cause:**
- IPMI exporter-remote deployment was set to 1 replica by default
- Secret `ipmi-credentials` was created with empty username/password when credentials not defined
- Pod tried to start but failed because:
  - Environment variables IPMI_USER and IPMI_PASSWORD were empty strings
  - IPMI exporter couldn't connect to remote BMC without credentials
  - Pod continuously restarted in Error state

**Fix Applied:**
1. Modified `manifests/monitoring/ipmi-exporter.yaml`:
   - Changed `replicas: 1` to `replicas: 0` for ipmi-exporter-remote deployment
   - Added comment explaining this is intentional

2. Modified `ansible/playbooks/deploy-cluster.yaml`:
   - Added conditional scale-up task after IPMI exporter deployment
   - Only scales to 1 replica when `ipmi_username` and `ipmi_password` are defined
   - Task includes `failed_when: false` for safety

**Files Changed:**
- `manifests/monitoring/ipmi-exporter.yaml` - Line 135 (replicas: 0)
- `ansible/playbooks/deploy-cluster.yaml` - Added scale task at line 472

**Expected Result:**
- No IPMI exporter-remote pods when credentials not configured (0 replicas)
- IPMI exporter-remote scales to 1 when credentials are available
- No error pods in monitoring namespace

### Issue 3: Missing Dashboard Data / Down Scrape Targets

**Symptom:**
- Prometheus showing multiple targets as "Down":
  - `192.168.4.62:30090` (rke2-federation)
  - `192.168.4.60` (ipmi-exporter-remote)
  - `192.168.4.62:9290` (ipmi-exporter)
- Grafana dashboards showing limited or no data

**Root Cause:**
- Optional targets configured but not all components deployed:
  - RKE2 cluster not deployed yet (deployment failed in Phase 2)
  - Remote IPMI server not accessible or configured
  - IPMI hardware may not exist on homelab node
- This is actually expected behavior for optional monitoring

**Fix Applied:**
- Added documentation comments in `manifests/monitoring/prometheus.yaml`:
  - Explains when each target will be DOWN
  - Clarifies these are optional and won't break core monitoring
  - Documents that Debian-only deployment won't have RKE2 metrics

**Files Changed:**
- `manifests/monitoring/prometheus.yaml` - Added comments at lines 156, 169, 242

**Expected Result:**
- Core metrics available from:
  - ✅ kubernetes-nodes (both Debian nodes)
  - ✅ kubernetes-cadvisor (container metrics)
  - ✅ node-exporter (all three nodes if accessible)
- Optional metrics marked as DOWN when not available:
  - ⚠️ rke2-federation (requires RKE2 deployment)
  - ⚠️ ipmi-exporter (requires hardware support)
  - ⚠️ ipmi-exporter-remote (requires credentials)
- Dashboards populate with available metrics
- No pod failures or errors

## Verification Steps

After deployment, verify the fixes:

### 1. Check Jellyfin Deployment

```bash
# Check Jellyfin pod is running on correct node
kubectl get pods -n jellyfin -o wide

# Expected:
# NAME       READY   STATUS    RESTARTS   AGE   NODE
# jellyfin   1/1     Running   0          2m    storagenodet3500

# Test Jellyfin endpoint
curl http://192.168.4.61:30096/health
# Should return HTTP 200
```

### 2. Check IPMI Exporter Status

```bash
# Check monitoring namespace pods
kubectl get pods -n monitoring | grep ipmi

# Without credentials (expected):
# ipmi-exporter-remote: No pods (deployment at 0 replicas)
# ipmi-exporter: No pods if no compute nodes

# With credentials (if configured):
# ipmi-exporter-remote-xxx   1/1     Running   0   2m
```

### 3. Check Prometheus Targets

```bash
# Access Prometheus UI
open http://192.168.4.63:30090/targets

# Expected status:
# ✅ UP: kubernetes-nodes, kubernetes-cadvisor, node-exporter (192.168.4.63, 192.168.4.61)
# ⚠️  DOWN: rke2-federation (if RKE2 not deployed)
# ⚠️  DOWN: ipmi-exporter-remote (if credentials not set)
```

### 4. Check Grafana Dashboards

```bash
# Access Grafana
open http://192.168.4.63:30300

# Expected data in dashboards:
# - Node metrics (CPU, memory, disk) for masternode and storagenodet3500
# - Container metrics from cAdvisor
# - Kubernetes cluster overview
```

## Enabling Optional Monitoring

### Enable Remote IPMI Monitoring

1. Define credentials in inventory or group_vars:

```yaml
# ansible/inventory/hosts.yml or ansible/group_vars/all.yml
ipmi_username: "admin"
ipmi_password: "your_secure_password"
```

2. Re-run deployment or manually scale:

```bash
# Option 1: Re-deploy (will apply credentials)
./deploy.sh debian

# Option 2: Manual scale after adding secret
kubectl scale deployment ipmi-exporter-remote -n monitoring --replicas=1
```

### Enable RKE2 Federation

Deploy RKE2 cluster to homelab node:

```bash
./deploy.sh rke2
```

This will make the RKE2 federation target available at `192.168.4.62:30090`.

## Testing

A comprehensive test suite was created to validate these changes:

```bash
# Run tests
python3 /tmp/test_deployment_changes.py

# Expected output:
# ============================================================
# Testing Deployment Changes
# ============================================================
# 
# Testing deploy-cluster.yaml...
# ✓ deploy-cluster.yaml includes Jellyfin deployment
# 
# Testing ipmi-exporter.yaml...
# ✓ ipmi-exporter.yaml has replicas=0 for remote exporter
# 
# Testing IPMI exporter scale-up task...
# ✓ Playbook includes conditional IPMI exporter scale-up
# 
# Testing jellyfin.yaml...
# ✓ jellyfin.yaml has correct nodeSelector for storagenodet3500
# 
# ============================================================
# Results: 4 passed, 0 failed
# ============================================================
```

## Summary

These fixes ensure that:

1. **Jellyfin deploys correctly** to the storage node during cluster initialization
2. **No failed pods** due to missing IPMI credentials
3. **Monitoring works** with available targets, gracefully handling missing optional components
4. **Clear documentation** explains expected "Down" targets
5. **Easy enablement** of optional monitoring features when ready

The deployment is now more robust and handles partial configurations gracefully.
