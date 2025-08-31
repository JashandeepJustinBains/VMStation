# VMStation Scripts Documentation

This directory contains operational scripts for VMStation infrastructure management.

## CrashLoopBackOff Fix Scripts (NEW!)

### `fix_k8s_dashboard_permissions.sh`
Fixes Kubernetes Dashboard CrashLoopBackOff issues related to directory permissions and certificate generation.

**Usage:**
```bash
# Diagnose dashboard permission issues
./scripts/fix_k8s_dashboard_permissions.sh

# Apply fixes automatically
./scripts/fix_k8s_dashboard_permissions.sh --auto-approve
```

### `validate_drone_config.sh`
Validates Drone CI configuration and tests GitHub integration setup.

**Usage:**
```bash
# Validate drone configuration
./scripts/validate_drone_config.sh
```

### `test_crashloop_fixes.sh`
Integration test script that validates and applies both drone and dashboard fixes.

**Usage:**
```bash
# Dry run test (recommended first)
./scripts/test_crashloop_fixes.sh

# Apply fixes
./scripts/test_crashloop_fixes.sh --apply
```

## Quick Start for CrashLoopBackOff Issues

1. **Identify the problem:**
   ```bash
   kubectl get pods -A | grep CrashLoopBackOff
   ```

2. **Run diagnostics:**
   ```bash
   ./scripts/diagnose_monitoring_permissions.sh
   ```

3. **For Drone issues:**
   ```bash
   # Check configuration
   ./scripts/validate_drone_config.sh
   
   # Fix by updating secrets and redeploying
   ansible-vault edit ansible/group_vars/secrets.yml
   ansible-playbook -i inventory.txt ansible/subsites/05-extra_apps.yaml --ask-vault-pass
   ```

4. **For Dashboard issues:**
   ```bash
   # Fix permissions
   ./scripts/fix_k8s_dashboard_permissions.sh --auto-approve
   ```

5. **Integration test:**
   ```bash
   # Test all fixes together
   ./scripts/test_crashloop_fixes.sh --apply
   ```

## Infrastructure Scripts

### Kubernetes (Primary)
- **`validate_k8s_monitoring.sh`** - Validates Kubernetes monitoring stack health
- **`fix_k8s_monitoring_pods.sh`** - **NEW!** Fixes CrashLoopBackOff pod issues with targeted remediation
- **`analyze_k8s_monitoring_diagnostics.sh`** - Analyzes diagnostic output and provides CLI remediation commands
- **`get_copilot_prompt.sh`** - Provides premium GitHub Copilot troubleshooting prompts for monitoring issues
- **`validate_infrastructure.sh`** - Auto-detects and validates current infrastructure mode

### Legacy Podman (Deprecated)
- **`validate_monitoring.sh`** - Legacy Podman monitoring validation
- **`fix_podman_metrics.sh`** - Fixes Podman metrics issues
- **`podman_metrics_diagnostic.sh`** - Diagnoses Podman metrics problems
- **`cleanup_podman_legacy.sh`** - Removes legacy Podman infrastructure

### Permission Management
- **`quick_permission_guide.sh`** - Quick reference for monitoring permission fixes
- **`diagnose_monitoring_permissions.sh`** - Comprehensive permission diagnostic tool
- **`fix_monitoring_permissions.sh`** - Automated permission fix script

### Premium GitHub Copilot Integration
- **`get_copilot_prompt.sh`** - Provides premium GitHub Copilot troubleshooting prompts for monitoring issues
  - `--show` - Template prompt (requires separate diagnostic gathering)
  - `--complete` - Ready-to-use prompt with embedded diagnostic data
  - `--copy` / `--copy-complete` - Copy prompts to clipboard
  - `--gather` - Collect basic cluster diagnostics

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

### For Kubernetes Infrastructure
```bash
# Fix monitoring pod CrashLoopBackOff issues (NEW!)
./scripts/fix_k8s_monitoring_pods.sh

# Validate monitoring stack
./scripts/validate_k8s_monitoring.sh

# Get premium Copilot troubleshooting prompt (template)
./scripts/get_copilot_prompt.sh --show

# Get complete prompt with embedded diagnostics
./scripts/get_copilot_prompt.sh --complete

# Gather diagnostic data for manual troubleshooting
./scripts/get_copilot_prompt.sh --gather

# Auto-detect and validate
./scripts/validate_infrastructure.sh

# Deploy infrastructure
./deploy_kubernetes.sh
```

### For Legacy Podman (Migration Path)
```bash
# Validate current Podman setup
./scripts/validate_monitoring.sh

# Fix Podman metrics issues
./scripts/fix_podman_metrics.sh

# Diagnose problems
./scripts/podman_metrics_diagnostic.sh

# Migrate to Kubernetes
./deploy_kubernetes.sh

# Clean up after migration
./scripts/cleanup_podman_legacy.sh
```

## Script Categories

### Validation Scripts
| Script | Purpose | Infrastructure |
|--------|---------|----------------|
| `validate_k8s_monitoring.sh` | Kubernetes monitoring validation | Kubernetes |
| `validate_infrastructure.sh` | Auto-detecting validation | Both |
| `validate_monitoring.sh` | Podman monitoring validation | Podman (Legacy) |

### Diagnostic Scripts
| Script | Purpose | Infrastructure |
|--------|---------|----------------|
| `analyze_k8s_monitoring_diagnostics.sh` | K8s monitoring issue analysis and CLI remediation | Kubernetes |
| `diagnose_monitoring_permissions.sh` | Monitoring permission analysis | Both |
| `podman_metrics_diagnostic.sh` | Podman metrics diagnostics | Podman (Legacy) |

### Fix Scripts
| Script | Purpose | Infrastructure |
|--------|---------|----------------|
| `fix_k8s_monitoring_pods.sh` | Fix Kubernetes pod CrashLoopBackOff issues | Kubernetes |
| `fix_monitoring_permissions.sh` | Fix monitoring permission issues | Both |
| `fix_podman_metrics.sh` | Fix Podman metrics issues | Podman (Legacy) |
| `fix_container_restarts.sh` | Fix container restart issues | Podman (Legacy) |

### Quick Reference
| Script | Purpose | Infrastructure |
|--------|---------|----------------|
| `quick_permission_guide.sh` | Permission fix guidance | Both |

### Migration Scripts
| Script | Purpose | Infrastructure |
|--------|---------|----------------|
| `cleanup_podman_legacy.sh` | Remove legacy Podman setup | Migration |

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