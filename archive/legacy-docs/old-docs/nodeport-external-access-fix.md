# NodePort External Access Fix

## Problem Statement

External machines (like development desktops) cannot access Kubernetes NodePort services (specifically Jellyfin on port 30096) even after running standard cluster communication fixes. The issue manifests as:

- Internal cluster communication works correctly
- NodePort services respond when accessed from cluster nodes  
- External machines on the same network (192.168.4.x) cannot reach NodePort services
- Connection timeouts when accessing `http://192.168.4.61:30096` from external machines

## Root Cause

The issue is caused by missing firewall rules and incomplete iptables configuration for NodePort external access:

1. **Missing UFW rules**: NodePort range (30000-32767) not explicitly allowed for external traffic
2. **Incomplete iptables rules**: kube-proxy may not have properly configured all NodePort forwarding rules
3. **Firewall blocking**: Default firewall settings block the NodePort range from external access

## Solution

### New Scripts Added

#### 1. `scripts/fix_nodeport_external_access.sh`
Comprehensive fix for NodePort external access issues:

- **UFW Configuration**: Adds rules for NodePort range (30000-32767) from local network
- **iptables Validation**: Ensures kube-proxy has created proper KUBE-NODEPORTS chains  
- **Direct iptables Rules**: Adds explicit ACCEPT rules for active NodePorts
- **Service Validation**: Tests NodePort accessibility from control plane
- **Jellyfin-specific Checks**: Special handling for Jellyfin pod and service status

**Usage:**
```bash
sudo ./scripts/fix_nodeport_external_access.sh
```

**Requirements:** Must run as root for firewall modifications

#### 2. `scripts/validate_nodeport_external_access.sh`
Validation script to test NodePort external access:

- **Firewall Rule Validation**: Checks UFW and iptables rules
- **NodePort Service Testing**: Tests all NodePort services in cluster
- **Jellyfin-specific Testing**: Detailed Jellyfin accessibility tests
- **External Access Guidance**: Provides commands for testing from external machines

**Usage:**
```bash
./scripts/validate_nodeport_external_access.sh
```

#### 3. `scripts/test_nodeport_external_access_fix.sh`
Test script to validate the fix implementation:

- **Script Validation**: Checks syntax and executability
- **Integration Testing**: Verifies integration with main fix script
- **Component Testing**: Validates all expected functionality is present

**Usage:**
```bash
./scripts/test_nodeport_external_access_fix.sh
```

### Integration with Existing Scripts

The fix has been integrated into the main cluster communication fix:

#### Updated: `scripts/fix_cluster_communication.sh`
- **Step 5**: Added NodePort external access fix after pod connectivity validation
- **Enhanced Messaging**: Updated success/failure messages to mention external access
- **Better Guidance**: Improved troubleshooting suggestions with new validation script

## How It Works

### 1. UFW Firewall Rules
```bash
# Allow NodePort range from local network
ufw allow from 192.168.0.0/16 to any port 30000:32767 comment "Kubernetes NodePorts"

# Allow specific NodePorts from anywhere
ufw allow 30096 comment "NodePort 30096"  # Jellyfin
```

### 2. iptables Rules
```bash
# Ensure KUBE-NODEPORTS chain exists (managed by kube-proxy)
iptables -t nat -L KUBE-NODEPORTS

# Add direct ACCEPT rules for NodePorts
iptables -A INPUT -p tcp --dport 30096 -j ACCEPT
iptables -A INPUT -p udp --dport 30096 -j ACCEPT
```

### 3. kube-proxy Restart
If kube-proxy iptables chains are missing or incomplete:
```bash
kubectl rollout restart daemonset/kube-proxy -n kube-system
```

## Usage Examples

### Running the Complete Fix
```bash
# Run comprehensive cluster communication fix (includes NodePort fix)
sudo ./scripts/fix_cluster_communication.sh
```

### Running Only NodePort Fix
```bash
# Run targeted NodePort external access fix
sudo ./scripts/fix_nodeport_external_access.sh
```

### Validating the Fix
```bash
# Validate NodePort external access configuration
./scripts/validate_nodeport_external_access.sh
```

### Testing from External Machine
After running the fix, test from development desktop:
```bash
# Test Jellyfin access from external machine
curl -v http://192.168.4.61:30096/    # Storage node
curl -v http://192.168.4.63:30096/    # Master node  
curl -v http://192.168.4.62:30096/    # Homelab node

# Or open in browser
http://192.168.4.61:30096/
```

## Troubleshooting

### If External Access Still Fails

1. **Check Network Connectivity**:
   ```bash
   ping 192.168.4.61  # Ensure basic connectivity
   ```

2. **Test Port Connectivity**:
   ```bash
   nc -v 192.168.4.61 30096  # Test if port is open
   ```

3. **Check External Firewall**:
   - Router/switch configuration
   - External machine firewall settings
   - ISP or network administrator restrictions

4. **Validate Cluster State**:
   ```bash
   kubectl get nodes                    # All nodes Ready
   kubectl get pods -n jellyfin         # Jellyfin pod Running
   kubectl get svc -n jellyfin          # Service has correct NodePort
   kubectl get endpoints -n jellyfin    # Service has valid endpoints
   ```

5. **Check UFW Status**:
   ```bash
   sudo ufw status numbered  # Verify rules exist
   ```

6. **Check iptables Rules**:
   ```bash
   sudo iptables -t nat -L KUBE-NODEPORTS  # kube-proxy rules
   sudo iptables -L INPUT | grep 30096     # Direct rules
   ```

### Common Issues

1. **"Connection refused"**: Service not running or not bound to correct interface
2. **"Connection timeout"**: Firewall blocking or routing issues  
3. **"No route to host"**: Network connectivity or routing problems
4. **Works locally but not externally**: Firewall configuration issues

## Files Modified

- `scripts/fix_nodeport_external_access.sh` (new)
- `scripts/validate_nodeport_external_access.sh` (new)  
- `scripts/test_nodeport_external_access_fix.sh` (new)
- `scripts/fix_cluster_communication.sh` (updated)

## Expected Outcome

After applying this fix:

1. **External machines can access NodePort services**: Development desktop can reach Jellyfin on `http://192.168.4.61:30096`
2. **Proper firewall configuration**: UFW rules allow NodePort traffic from local network
3. **Complete iptables setup**: All necessary forwarding rules in place
4. **Reliable access**: NodePort services accessible from all cluster nodes externally
5. **Monitoring integration**: Can access Grafana/Prometheus externally if needed

The fix addresses the specific issue mentioned in the problem statement where external machines could not access Jellyfin despite successful cluster communication fixes.