# Kubespray Automated Deployment System

This directory contains the automated deployment system for VMStation Kubernetes cluster using Kubespray.

## Overview

The automation system provides a complete, hands-off deployment of Kubernetes using Kubespray with built-in error handling, remediation, and comprehensive logging.

## Components

### 1. Main Orchestration Script
**File**: `scripts/ops-kubespray-automation.sh`

The main orchestration script that automates the entire Kubespray deployment workflow. It handles:
- Environment setup and SSH key management
- File backup and git operations
- Inventory normalization and validation
- Preflight checks with automatic remediation
- Kubespray cluster deployment with retry logic
- Kubeconfig distribution
- Cluster health verification
- CNI troubleshooting and fixes
- Wake-on-LAN for sleeping nodes
- Monitoring and infrastructure deployment
- Smoke testing and validation
- Comprehensive reporting and artifact collection

### 2. GitHub Actions Workflow
**File**: `.github/workflows/kubespray-deployment.yml`

GitHub Actions workflow that runs the orchestration script in a GitHub-hosted runner. Features:
- Automatic dependency installation
- SSH key management from secrets
- Artifact collection (logs, kubeconfig, reports)
- Deployment status reporting
- Support for workflow inputs (skip options)

### 3. Idempotent Fix Playbooks
**Directory**: `ansible/playbooks/fixes/`

Auto-generated Ansible playbooks for common fixes:
- `disable-swap.yml` - Disable swap on all nodes
- `load-kernel-modules.yml` - Load required kernel modules
- `restart-container-runtime.yml` - Restart containerd

## Usage

### Running via GitHub Actions

1. Go to your repository on GitHub
2. Navigate to Actions → Kubespray Automated Deployment
3. Click "Run workflow"
4. Optionally configure skip options
5. Monitor the workflow execution
6. Download artifacts when complete

### Running Locally

```bash
# Set required environment variables
export VMSTATION_SSH_KEY="$(cat ~/.ssh/id_vmstation_ops)"
export REPO_ROOT="/path/to/VMStation"
export SSH_KEY_PATH="/tmp/id_vmstation_ops"

# Run the automation script
bash scripts/ops-kubespray-automation.sh
```

## Environment Variables

The following environment variables control the automation:

| Variable | Default | Description |
|----------|---------|-------------|
| `REPO_ROOT` | `/github/workspace` | Repository root directory |
| `KUBESPRAY_DIR` | `$REPO_ROOT/.cache/kubespray` | Kubespray installation directory |
| `KUBESPRAY_INVENTORY` | `$KUBESPRAY_DIR/inventory/mycluster/inventory.ini` | Kubespray inventory file |
| `MAIN_INVENTORY` | `$REPO_ROOT/ansible/inventory/hosts.yml` | Main inventory file |
| `SSH_KEY_PATH` | `/tmp/id_vmstation_ops` | SSH private key path |
| `VMSTATION_SSH_KEY` | - | SSH private key content (from secret) |

## Workflow Steps

The automation follows these steps in order:

1. **Prepare Runtime** - Setup directories, SSH keys, git config
2. **Backup Files** - Backup important files with timestamps
3. **Normalize Inventory** - Ensure inventory format is correct
4. **Validate Inventory** - Test connectivity to all nodes
5. **Preflight Checks** - Run RHEL10 preflight with remediation
6. **Setup Kubespray** - Clone and configure Kubespray
7. **Deploy Cluster** - Run Kubespray cluster.yml with retries
8. **Setup Kubeconfig** - Distribute admin kubeconfig
9. **Verify Cluster** - Check node readiness and CNI health
10. **Deploy Monitoring** - Deploy monitoring stack
11. **Deploy Infrastructure** - Deploy infrastructure services
12. **Run Smoke Tests** - Validate basic cluster functionality
13. **Generate Report** - Create JSON report with status
14. **Cleanup** - Security cleanup

## Artifacts

The automation generates comprehensive artifacts:

### Log Files
- `ansible-run-logs/main.log` - Main orchestration log
- `ansible-run-logs/preflight.log` - Preflight check output
- `ansible-run-logs/kubespray-cluster.log` - Cluster deployment log
- `ansible-run-logs/cluster-verification.log` - Verification output
- `ansible-run-logs/monitoring-deployment.log` - Monitoring deployment
- `ansible-run-logs/infrastructure-deployment.log` - Infrastructure deployment
- `ansible-run-logs/smoke-test.log` - Smoke test results

### Reports
- `ops-report-<timestamp>.json` - JSON report with deployment status

### Diagnostic Bundle (on failure)
- `diagnostic-bundle/network-diagnostics.txt` - Network connectivity tests
- `diagnostic-bundle/ssh-diagnostics.txt` - SSH connection tests
- `diagnostic-bundle/inventory-diagnostics.txt` - Inventory validation
- `diagnostic-bundle/environment-diagnostics.txt` - Environment details

### Backups
- `.git/ops-backups/<timestamp>/` - Backup of modified files

## Error Handling

The automation includes comprehensive error handling:

### Automatic Remediation
- **Python missing**: Installs python3 via package manager
- **Swap enabled**: Disables swap and removes fstab entries
- **Kernel modules**: Loads br_netfilter and overlay
- **Container runtime**: Restarts containerd and kubelet
- **Sleeping nodes**: Sends Wake-on-LAN packets
- **Network issues**: Creates diagnostic bundle

### Retry Logic
- Cluster deployment: Up to 3 attempts with remediation
- Inventory validation: 2 attempts with WoL between
- Preflight checks: 2 attempts with remediation

### Fail-Safe Stops
The automation stops immediately if:
- SSH key is not available
- No network connectivity to any host after WoL
- Cluster deployment fails after all retries
- Kubeconfig is not generated

## Security

### SSH Key Handling
- SSH keys are written to `/tmp/id_vmstation_ops` with mode 0600
- Keys are never echoed or logged
- Keys are only available in GitHub Actions secrets
- Cleanup reminder is logged at the end

### Kubeconfig Security
- Admin kubeconfig stored in `/tmp/admin.conf` with mode 0600
- Not committed to repository
- Included in .gitignore
- Available as GitHub Actions artifact with 7-day retention

### Backup Safety
- All modified files are backed up before changes
- Backups stored in `.git/ops-backups/<timestamp>/`
- Each backup is committed to git history
- Timestamped for easy identification

## Troubleshooting

### Network Unreachable
If nodes are unreachable:
1. Check diagnostic bundle for connectivity details
2. Verify Wake-on-LAN MAC addresses in inventory
3. Manually wake nodes: `wakeonlan <MAC>`
4. Check firewall rules on nodes
5. Verify SSH key has access to all nodes

### Preflight Failures
If preflight checks fail:
1. Review `preflight.log` for specific errors
2. Check if Python is installed on compute nodes
3. Verify swap is disabled
4. Ensure SELinux is in permissive mode (RHEL)
5. Check firewall ports are open

### Cluster Deployment Failures
If cluster deployment fails:
1. Review `kubespray-cluster.log` for error messages
2. Check if containerd is running on all nodes
3. Verify kubelet service status
4. Ensure kernel modules are loaded
5. Check for port conflicts

### CNI Not Working
If CNI pods are failing:
1. Review `cluster-verification.log`
2. Check kernel modules: `lsmod | grep br_netfilter`
3. Verify network policies don't block CNI
4. Restart CNI pods: `kubectl -n kube-system delete pods -l k8s-app=<cni-name>`
5. Check node iptables rules

## Success Criteria

The deployment is successful when:
- ✓ All nodes show Ready status: `kubectl get nodes`
- ✓ All kube-system pods are Running/Ready
- ✓ Monitoring stack deploys successfully
- ✓ Infrastructure services deploy successfully
- ✓ Smoke test passes
- ✓ No critical errors in logs

## Monitoring Deployment

The automation deploys the monitoring stack which includes:
- **Prometheus** - Metrics collection and alerting
- **Grafana** - Visualization dashboards
- **Loki** - Log aggregation
- **Node Exporter** - Host metrics
- **Kube State Metrics** - Kubernetes metrics

Access monitoring after deployment:
```bash
# Get Grafana URL
kubectl -n monitoring get svc grafana

# Forward port for local access
kubectl -n monitoring port-forward svc/grafana 3000:3000
```

## Infrastructure Services

The automation deploys infrastructure services:
- **NTP/Chrony** - Time synchronization
- **Syslog** - Centralized logging
- **Kerberos** - Authentication (optional)

## Next Steps After Deployment

1. **Verify Cluster Health**:
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

2. **Access Grafana**:
   ```bash
   kubectl -n monitoring port-forward svc/grafana 3000:3000
   # Default credentials: admin/admin
   ```

3. **Deploy Applications**:
   ```bash
   kubectl apply -f your-app.yaml
   ```

4. **Setup Auto-Sleep** (optional):
   ```bash
   ./deploy.sh setup --enable-autosleep
   ```

5. **Test Sleep/Wake Cycle**:
   ```bash
   ./tests/test-sleep-wake-cycle.sh
   ```

## Contributing

When modifying the automation:
1. Test changes in a development environment first
2. Update this README with any new features
3. Add new idempotent fix playbooks for common issues
4. Maintain backward compatibility with existing inventory
5. Preserve all safety checks and backups

## Support

For issues or questions:
1. Check the diagnostic bundle first
2. Review logs in artifacts directory
3. Search existing GitHub issues
4. Create a new issue with logs attached

## References

- [Kubespray Documentation](https://kubespray.io/)
- [VMStation Repository](https://github.com/JashandeepJustinBains/VMStation)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
