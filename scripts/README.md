# VMStation Scripts Documentation

This directory historically contained many operational scripts for VMStation.

NOTE: As part of a cleanup to reduce technical debt, large legacy scripts have been archived under `ansible/archive/playbooks` and `ansible/archive/plays`.
The active deployment flow is now focused under `ansible/playbooks/deploy-cluster.yaml` and `ansible/roles/`.

Use the Ansible minimal deploy instead of the legacy scripts:

```powershell
ansible-playbook -i ansible/inventory.txt ansible/playbooks/deploy-cluster.yaml
```

## Infrastructure Scripts

### Core Infrastructure Scripts
- **`enhanced_kubeadm_join.sh`** - Enhanced Kubernetes join process with comprehensive validation
- **`comprehensive_worker_setup.sh`** - Complete worker node setup and configuration
- **`fix_cluster_communication.sh`** - Fixes cluster communication and networking issues
- **`fix_remaining_pod_issues.sh`** - Fixes common pod issues including Jellyfin readiness and kube-proxy
- **`validate_pod_health.sh`** - Validates pod health and cluster status
- **`vmstation_status.sh`** - Comprehensive cluster status and diagnostic information

### CNI and Network Fixes
- **`fix_cni_bridge_conflict.sh`** - Fixes CNI bridge IP conflicts causing ContainerCreating errors
- **`fix_worker_node_cni.sh`** - Fixes worker node CNI communication issues
- **`fix_flannel_mixed_os.sh`** - Fixes Flannel issues in mixed OS environments
- **`validate_cluster_communication.sh`** - Validates cluster communication and NodePort services

### Diagnostic and Troubleshooting Scripts  
- **`diagnose_remaining_pod_issues.sh`** - Analyzes specific pod failures and issues
- **`gather_worker_diagnostics.sh`** - Comprehensive worker node diagnostic collection
- **`run_network_diagnosis.sh`** - Network diagnosis and connectivity testing
- **`check_coredns_status.sh`** - CoreDNS status and configuration validation

### Validation Scripts
- **`validate_join_prerequisites.sh`** - Comprehensive validation before kubeadm join
- **`validate_post_wipe_functionality.sh`** - Validates post-wipe worker join functionality
- **`validate_pod_connectivity.sh`** - Tests pod-to-pod CNI communication
- **`validate_nodeport_external_access.sh`** - Validates external access to NodePort services

## Troubleshooting Workflow Options

### Option 1: Template Prompt (Traditional)
1. Get template prompt: `./scripts/get_copilot_prompt.sh --show`
2. Copy to premium GitHub Copilot agent
3. Gather diagnostics: `./scripts/get_copilot_prompt.sh --gather`
4. Provide diagnostic output to agent
5. Follow agent's recommendations

### Option 2: Complete Prompt (Ready-to-Use)
1. Get complete prompt: `./scripts/get_copilot_prompt.sh --complete`
2. Copy directly to premium GitHub Copilot agent (includes diagnostics)
3. Follow agent's recommendations

### Container Management (Legacy)
- **`fix_container_restarts.sh`** - Fixes container restart issues in Podman
- **`validate_container_fixes.sh`** - Validates container restart fixes
- **`verify_container_fixes.sh`** - Verifies container fixes
- **`validate_grafana_fix.sh`** - Validates Grafana-specific fixes

## Quick Reference

### Core Deployment and Setup
```bash
# Main cluster deployment
./deploy-cluster.sh

# Enhanced worker join process
./scripts/enhanced_kubeadm_join.sh

# Comprehensive worker setup
./scripts/comprehensive_worker_setup.sh

# Get cluster status and diagnostics
./scripts/vmstation_status.sh
```

### Fixing Common Issues
```bash
# Fix cluster communication problems
./scripts/fix_cluster_communication.sh

# Fix remaining pod issues (Jellyfin, kube-proxy, etc.)
./scripts/fix_remaining_pod_issues.sh

# Fix CNI bridge conflicts
./scripts/fix_cni_bridge_conflict.sh

# Fix worker node CNI communication
./scripts/fix_worker_node_cni.sh
```

### Validation and Diagnostics
```bash
# Validate pod health
./scripts/validate_pod_health.sh

# Validate cluster communication
./scripts/validate_cluster_communication.sh

# Diagnose pod issues
./scripts/diagnose_remaining_pod_issues.sh

# Gather worker diagnostics
./scripts/gather_worker_diagnostics.sh
```

## Script Categories

### Core Infrastructure Scripts
| Script | Purpose | Size (lines) |
|--------|---------|-------------|
| `enhanced_kubeadm_join.sh` | Enhanced Kubernetes join process | 1388 |
| `comprehensive_worker_setup.sh` | Complete worker node setup | 481 |
| `fix_cluster_communication.sh` | Cluster communication fixes | 705 |
| `fix_remaining_pod_issues.sh` | Pod issue remediation | 673 |

### Network and CNI Scripts
| Script | Purpose | Size (lines) |
|--------|---------|-------------|
| `fix_cni_bridge_conflict.sh` | CNI bridge IP conflict fixes | 378 |
| `fix_worker_node_cni.sh` | Worker CNI communication fixes | 423 |
| `fix_flannel_mixed_os.sh` | Mixed OS Flannel fixes | 403 |
| `validate_cluster_communication.sh` | Cluster communication validation | 339 |

### Diagnostic and Validation Scripts  
| Script | Purpose | Size (lines) |
|--------|---------|-------------|
| `gather_worker_diagnostics.sh` | Worker diagnostic collection | 453 |
| `validate_join_prerequisites.sh` | Pre-join validation | 398 |
| `diagnose_remaining_pod_issues.sh` | Pod issue diagnosis | 195 |
| `validate_pod_health.sh` | Pod health validation | 109 |

## Migration Workflow

1. **Validate Current Setup**
   ```bash
   ./scripts/validate_monitoring.sh
   ```

2. **Deploy Kubernetes**
   ```bash
   ./deploy_kubernetes.sh
   ```

3. **Validate New Setup**
   ```bash
   ./scripts/validate_k8s_monitoring.sh
   ```

4. **Clean Up Legacy**
   ```bash
   ./scripts/cleanup_podman_legacy.sh
   ```

## Troubleshooting

### Permission Issues (Common)
If monitoring pods are stuck in Pending/Unknown status:
```bash
# Quick guidance
./scripts/quick_permission_guide.sh

# Detailed diagnosis
./scripts/diagnose_monitoring_permissions.sh

# Automated fix (requires sudo)
sudo ./scripts/fix_monitoring_permissions.sh
```

Critical directories that need read/write access:
- `/srv/monitoring_data` - Main monitoring storage
- `/var/log` - Log files for promtail collection  
- `/var/promtail` - Promtail working directory
- `/opt/promtail` - Promtail configuration

### Kubernetes Issues
```bash
# Quick fix for CrashLoopBackOff pods (NEW!)
./scripts/fix_k8s_monitoring_pods.sh

# Check cluster status
kubectl get nodes
kubectl get pods -n monitoring

# Check service endpoints
kubectl get svc -n monitoring

# View pod logs
kubectl logs -n monitoring deployment/grafana

# Analyze diagnostic output for issues
./scripts/analyze_k8s_monitoring_diagnostics.sh
```

### Legacy Podman Issues
```bash
# Check container status
podman ps -a

# View container logs
podman logs <container-name>

# Fix metrics specifically
./scripts/fix_podman_metrics.sh
```

## Environment Detection

The `validate_infrastructure.sh` script automatically detects your infrastructure:

- **Kubernetes**: Checks for `kubectl` and cluster connectivity
- **Podman**: Checks for `podman` and monitoring pod
- **Configuration**: Falls back to `ansible/group_vars/all.yml`

## Best Practices

1. **Always validate** before and after changes
2. **Use auto-detection** with `validate_infrastructure.sh`
3. **Back up data** before migration
4. **Test changes** in development first
5. **Monitor logs** during deployments

## Legacy Support

Legacy Podman scripts are maintained for:
- Migration scenarios
- Troubleshooting existing setups
- Reference documentation

New deployments should use Kubernetes infrastructure.

## Output Interpretation

### Success Indicators
- ✅ Green checkmarks indicate healthy services
- 📊 Service endpoints responding correctly
- 🔍 All monitoring targets are up

### Warning Indicators  
- ⚠️ Yellow warnings for non-critical issues
- 📝 Configuration recommendations
- 🔄 Services starting or restarting

### Error Indicators
- ❌ Red errors require immediate attention
- 🚨 Service failures or connectivity issues
- 💥 Infrastructure problems

## Getting Help

- **Documentation**: Check `docs/` directory
- **Logs**: Use script output and system logs
- **Validation**: Run validation scripts for health checks
- **Migration**: Follow `docs/MIGRATION_GUIDE.md`