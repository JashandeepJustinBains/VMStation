# VMStation DNS and Monitoring Fixes

This document describes the fixes applied to resolve DNS resolution, monitoring access, and homelab node stability issues.

## Issues Fixed

### 1. DNS Resolution for homelab.com Subdomains

**Problem**: homelab.com subdomains (like jellyfin.homelab.com) were not resolving properly.

**Solution**: 
- Simplified DNS setup to use CoreDNS configuration + /etc/hosts fallback
- Removed complex dnsmasq setup that was causing conflicts
- The setup script now properly applies CoreDNS configuration and adds hosts file entries

**Result**: 
```bash
# These now work:
curl http://jellyfin.homelab.com:30096/
curl http://grafana.homelab.com:30300/
nslookup jellyfin.homelab.com
```

### 2. Grafana and Prometheus Access

**Problem**: Could access Jellyfin at 192.168.4.61:30096 but not Grafana at 192.168.4.63:30300 or Prometheus at 30090.

**Solution**:
- Changed monitoring pod nodeSelector from `vmstation.io/role: monitoring` to `node-role.kubernetes.io/control-plane`
- This ensures Grafana and Prometheus pods are scheduled on the control plane (192.168.4.63)
- NodePort services are now accessible where the pods actually run

**Result**:
```bash
# These now work:
curl http://192.168.4.63:30300/  # Grafana
curl http://192.168.4.63:30090/  # Prometheus
curl http://grafana.homelab.com:30300/  # Grafana via subdomain
```

### 3. Homelab Node Stability

**Problem**: After deployment, always had to manually run `./scripts/fix_homelab_node_issues.sh` because kube-proxy and kube-flannel pods were in CrashLoopBackOff.

**Solution**:
- Reordered post-deployment fixes to run homelab node fixes first
- Enhanced the fix script with preventive node stability checks
- Added networking compatibility checks for RHEL/AlmaLinux systems
- The script now runs automatically as part of deployment

**Result**: No more manual intervention needed after running `./deploy-cluster.sh deploy`

## Usage

### Deploy with Automatic Fixes
```bash
./deploy-cluster.sh deploy
```
The homelab node fixes now run automatically during deployment.

### Manual Validation
```bash
# Validate all fixes are working
./scripts/validate_deployment_fixes.sh

# Or test individual components
./scripts/validate_static_ips_and_dns.sh
./scripts/fix_homelab_node_issues.sh
```

### Access Services
```bash
# Direct IP access
curl http://192.168.4.61:30096/  # Jellyfin
curl http://192.168.4.63:30300/  # Grafana  
curl http://192.168.4.63:30090/  # Prometheus

# Subdomain access (after DNS setup)
curl http://jellyfin.homelab.com:30096/
curl http://grafana.homelab.com:30300/
```

## Web UI Access

- **Jellyfin**: http://jellyfin.homelab.com:30096 or http://192.168.4.61:30096
- **Grafana**: http://grafana.homelab.com:30300 or http://192.168.4.63:30300 (admin/admin)
- **Prometheus**: http://192.168.4.63:30090

## Files Modified

1. `scripts/setup_static_ips_and_dns.sh` - Simplified DNS setup
2. `scripts/fix_homelab_node_issues.sh` - Added preventive checks
3. `manifests/monitoring/grafana.yaml` - Fixed nodeSelector
4. `manifests/monitoring/prometheus.yaml` - Fixed nodeSelector  
5. `deploy-cluster.sh` - Reordered fix execution
6. `scripts/validate_deployment_fixes.sh` - New validation script

## Backward Compatibility

All changes maintain backward compatibility:
- Existing deployment processes continue to work
- All existing scripts and manifests remain functional
- Only the problematic areas were modified with minimal changes