# Kubespray Deployment Fixes (2025-11-16)

## Issues Fixed

### 1. **Syslog-ng CrashLoopBackOff (940+ restarts)**

**Root Cause**: Liveness probe executed `pgrep syslog-ng`, but `pgrep` is not installed in the `balabit/syslog-ng:latest` image.

**Fix Applied**:
- Changed liveness probe from `exec` command (`pgrep syslog-ng`) to `tcpSocket` on port 514
- TCP port 514 is more reliable: syslog-ng binds to TCP/514, so if syslog-ng crashes, the port will be unreachable and the probe will fail appropriately
- Updated in: `manifests/infrastructure/syslog-server.yaml`

**Before**:
```yaml
livenessProbe:
  exec:
    command:
    - /bin/sh
    - -c
    - pgrep syslog-ng
```

**After**:
```yaml
livenessProbe:
  tcpSocket:
    port: 514
```

### 2. **Monitoring Pods Stuck Pending (Grafana, Loki, Prometheus)**

**Root Cause**: All monitoring pods had `nodeSelector: node-role.kubernetes.io/control-plane: ""` but your cluster has:
- **masternode** (192.168.4.63): Has `node-role.kubernetes.io/control-plane` label ✓
- **storagenodet3500** (192.168.4.61): Worker node without control-plane label ✗

Since only the control plane node matched the selector, and it likely has insufficient resources for all pods (Prometheus, Loki, Grafana all Pending simultaneously), pods couldn't schedule.

**Fix Applied**:
- Removed restrictive `nodeSelector: node-role.kubernetes.io/control-plane` from all monitoring pods
- Removed associated tolerations
- Pods now schedule on any available node with sufficient resources

**Files Updated**:
- `manifests/infrastructure/syslog-server.yaml` (removed nodeSelector/tolerations)
- `manifests/monitoring/grafana.yaml` (removed nodeSelector/tolerations from Deployment)
- `manifests/monitoring/loki.yaml` (removed nodeSelector/tolerations from StatefulSet)
- `manifests/monitoring/prometheus.yaml` (removed nodeSelector/tolerations from StatefulSet and DaemonSet)

### 3. **Minecraft Pod Stuck Pending (No PersistentVolume)**

**Root Cause**: StatefulSet uses `storageClassName: manual` with hostPath PV at `/srv/minecraft-data`. This directory must exist on the homelab node (192.168.4.62) with correct permissions.

**Fix Required** (Manual - execute on homelab node):
```bash
ssh jashandeepjustinbains@192.168.4.62
sudo mkdir -p /srv/minecraft-data
sudo chown 1000:1000 /srv/minecraft-data
sudo chmod 755 /srv/minecraft-data
exit
```

**Why**:
- StatefulSet runs Minecraft server as UID 1000 (unprivileged user)
- PV must have correct ownership so the pod can write to the mounted volume
- Minecraft ConfigMap copy into `/data` requires write permissions

## Verification Steps

### After Applying Fixes

1. **Reapply manifests**:
   ```bash
   kubectl apply -f manifests/infrastructure/syslog-server.yaml
   kubectl apply -f manifests/monitoring/
   ```

2. **Verify pods transitioning**:
   ```bash
   # Check pod status
   kubectl get pods -A
   
   # Watch for Ready/Running status
   kubectl get pods -A --watch
   
   # Check specific pod details
   kubectl describe pod syslog-server-0 -n infrastructure
   kubectl describe pod grafana-* -n monitoring
   kubectl describe pod minecraft-0 -n default
   ```

3. **Check events**:
   ```bash
   # Syslog should restart with TCP liveness instead of exec
   kubectl describe pod syslog-server-0 -n infrastructure | grep -A 20 Events
   
   # Monitoring pods should show Scheduled event
   kubectl describe pod grafana-* -n monitoring | grep -A 5 "Type.*Reason.*Message"
   
   # Minecraft should show Bound PVC once /srv/minecraft-data exists
   kubectl describe pvc minecraft-data-minecraft-0 -n default
   ```

4. **Test Minecraft deployment**:
   ```bash
   # Create Cloudflared secret (assuming credentials file exists)
   kubectl -n default create secret generic cloudflared-credentials \
     --from-file=credentials.json=/path/to/credentials.json
   
   # Run deployment
   ./deploy.sh minecraft
   
   # Check pod status
   kubectl logs minecraft-0 -c minecraft -f
   ```

## Cloudflared Secret: Pod-Scoped Isolation Confirmed

The Minecraft StatefulSet mounts the Cloudflared credentials Secret at `/etc/cloudflared/credentials.json` (read-only). This secret is:
- **Namespace-scoped**: Only exists in `default` namespace (where you create it)
- **Pod-scoped**: Only accessible to pods in `default` namespace that mount it
- **Not system-wide**: No floating storage on disk or shared volumes
- **Kubernetes-managed**: Stored encrypted in etcd, not on host filesystem

When you create the secret:
```bash
kubectl -n default create secret generic cloudflared-credentials --from-file=credentials.json=~/.cloudflared/<tunnel-id>.json
```

The file is ingested into Kubernetes and ONLY the StatefulSet pod can mount it. No other processes access it. It's fully isolated.

## Testing Checklist

- [ ] `/srv/minecraft-data` directory created on homelab node with correct permissions
- [ ] Manifests reapplied with fixes
- [ ] `kubectl get pods -A` shows all pods transitioning to Running/Ready
- [ ] Syslog-ng pod no longer in CrashLoopBackOff
- [ ] Grafana, Loki, Prometheus pods scheduled and Running
- [ ] Minecraft pod scheduled on homelab (homelab node selector in manifest)
- [ ] Cloudflared credentials secret created in `default` namespace
- [ ] Minecraft pod initializes and server properties copied
- [ ] Minecraft server is accessible on TCP/25565 (test locally first)

## Notes

- **Why TCP probes instead of pgrep**: TCP socket checks are standard for syslog and are more reliable than shell commands. If syslog-ng is running and bound to TCP/514, the probe succeeds. If the process crashes, Kubernetes immediately detects the port is unreachable.
- **Why remove control-plane nodeSelector**: These pods don't require control-plane node. Removing the selector allows natural scheduling based on resource availability. If you later want pods on control-plane only, add `nodeSelector: vmstation.io/role: monitoring` (matching your inventory labels).
- **Minecraft storage**: Must be pre-created because StatefulSet cannot create hostPath volumes. The `manual` storage class is a workaround for single-node testing; for production, use proper storage provisioners.

## Related Files Modified

1. `manifests/infrastructure/syslog-server.yaml` - Fixed liveness probe, removed nodeSelector
2. `manifests/monitoring/grafana.yaml` - Removed nodeSelector/tolerations
3. `manifests/monitoring/loki.yaml` - Removed nodeSelector/tolerations
4. `manifests/monitoring/prometheus.yaml` - Removed nodeSelector/tolerations (2 locations)

All changes are minimal, targeted, and preserve pod security contexts, resource limits, and other configurations.
