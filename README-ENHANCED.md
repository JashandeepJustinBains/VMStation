# VMStation Enhanced Deployment

## Quick Start

Replace post-deployment fix scripts with integrated Kubernetes deployment:

```bash
# Full deployment with all enhancements
./deploy-enhanced.sh full

# Dry run to see what would be done
DRY_RUN=true ./deploy-enhanced.sh full
```

## What's Enhanced

This enhanced deployment **eliminates the need** for these post-deployment fix scripts:

- ❌ `fix_homelab_node_issues.sh` 
- ❌ `fix_remaining_pod_issues.sh`
- ❌ `fix_jellyfin_cni_bridge_conflict.sh`

By integrating their functionality directly into the Ansible deployment process.

## Enhanced Features

### 🔧 CNI Bridge Conflict Prevention
- **Problem**: `cni0` bridge IP conflicts causing "already has an IP address different from X" errors
- **Solution**: Enhanced Flannel DaemonSet with init container cleanup and proper bridge management

### 📍 CoreDNS Control-Plane Scheduling  
- **Problem**: CoreDNS pods scheduling on worker nodes causing DNS issues
- **Solution**: Hard node affinity requirements ensuring CoreDNS stays on control-plane

### 🔄 kube-proxy Compatibility
- **Problem**: kube-proxy CrashLoopBackOff due to iptables/nftables conflicts
- **Solution**: Enhanced ConfigMap with proper iptables mode and compatibility settings

### 🎥 Enhanced Jellyfin Deployment
- **Problem**: Jellyfin readiness failures and networking issues
- **Solution**: Improved health checks, init containers, and CNI conflict detection

### ✅ Comprehensive Validation
- **Problem**: Issues discovered only after deployment completion
- **Solution**: Network validation at each deployment stage with automated remediation

## Deployment Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `full` | Complete cluster + applications | New deployments |
| `cluster` | Kubernetes cluster only | Infrastructure setup |
| `apps` | Monitoring applications only | Add monitoring to existing cluster |
| `jellyfin` | Enhanced Jellyfin only | Media server deployment |
| `validate` | Network validation only | Troubleshooting |

## Quick Examples

```bash
# Full enhanced deployment
./deploy-enhanced.sh full

# Just the cluster with network fixes
./deploy-enhanced.sh cluster

# Deploy Jellyfin with CNI bridge fixes
./deploy-enhanced.sh jellyfin

# Validate current network health
./deploy-enhanced.sh validate

# See what would be deployed (dry run)
DRY_RUN=true ./deploy-enhanced.sh full
```

## Migration from Legacy Deployment

### For New Deployments
Use the enhanced deployment from the start:
```bash
./deploy-enhanced.sh full
```

### For Existing Deployments
Apply enhancements gradually:
```bash
# 1. Validate current state
./deploy-enhanced.sh validate

# 2. Apply network enhancements
kubectl apply -f manifests/network/

# 3. Enhance Jellyfin deployment
./deploy-enhanced.sh jellyfin
```

### Troubleshooting Migration
If issues persist, temporary fallback to legacy scripts:
```bash
# Legacy scripts (should not be needed after enhancement)
./scripts/fix_homelab_node_issues.sh
./scripts/fix_remaining_pod_issues.sh  
./scripts/fix_jellyfin_cni_bridge_conflict.sh
```

## Key Files

### Enhanced Manifests
- `manifests/network/coredns-deployment.yaml` - Hard control-plane scheduling
- `manifests/network/kube-proxy-configmap.yaml` - iptables compatibility  
- `manifests/network/flannel-cni-config.yaml` - CNI bridge cleanup
- `manifests/network/flannel-enhanced-daemonset.yaml` - Enhanced Flannel with init containers
- `manifests/jellyfin/jellyfin.yaml` - Enhanced Jellyfin deployment

### Enhanced Playbooks
- `ansible/plays/setup-cluster.yaml` - Cluster setup with integrated fixes
- `ansible/plays/deploy-apps.yaml` - Applications with network validation
- `ansible/plays/jellyfin-enhanced.yml` - Enhanced Jellyfin deployment
- `ansible/plays/templates/network-validation-tasks.yaml` - Network validation tasks

### Deployment Scripts  
- `deploy-enhanced.sh` - Main enhanced deployment script
- `deploy-cluster.sh` - Original deployment script (still supported)

## Benefits

### ✅ Proactive Problem Prevention
- Issues prevented rather than fixed after occurrence
- Proper Kubernetes manifests ensure correct configuration
- Validation catches problems early

### ✅ Reduced Manual Intervention  
- No need for post-deployment fix scripts
- Self-healing deployment process
- Automated remediation of common issues

### ✅ Better Reliability
- Comprehensive validation at each stage
- Proper dependencies and ordering
- Enhanced error handling and recovery

### ✅ Improved Maintainability
- All fixes integrated into standard deployment
- Proper Kubernetes resource management
- Clear documentation and troubleshooting

## Documentation

- [📋 Enhanced Deployment Guide](docs/ENHANCED_DEPLOYMENT_GUIDE.md) - Complete implementation details
- [🔧 Original Fix Scripts Analysis](docs/fix_cluster_communication.md) - What was fixed and why
- [🏠 Homelab Node Fixes](docs/HOMELAB_NODE_FIXES.md) - CoreDNS and Flannel issues
- [🎯 Simplified Deployment](SIMPLIFIED-DEPLOYMENT.md) - Alternative simple approach

## Support

If the enhanced deployment doesn't resolve all issues:

1. **Check logs**: Enhanced deployment provides detailed logging
2. **Run validation**: `./deploy-enhanced.sh validate`  
3. **Review documentation**: [Enhanced Deployment Guide](docs/ENHANCED_DEPLOYMENT_GUIDE.md)
4. **Temporary fallback**: Use original fix scripts while investigating

The goal is to eliminate the need for post-deployment fix scripts entirely through proper Kubernetes deployment practices.