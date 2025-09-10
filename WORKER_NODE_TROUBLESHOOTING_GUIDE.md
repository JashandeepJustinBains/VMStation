# Worker Node Troubleshooting Guide

This guide documents the enhanced worker node troubleshooting workflow for VMStation Kubernetes cluster.

## Overview

The worker node troubleshooting system provides three approaches:

1. **Integrated Workflow** (Recommended) - Automated process with structured output
2. **Manual Steps** - Individual script execution for detailed control
3. **Enhanced Deployment** - Automatic log collection during cluster deployment

## Integrated Troubleshooting Workflow

### Quick Start
```bash
# Run the integrated troubleshooting workflow
sudo ./worker_node_troubleshoot_integration.sh
```

### What It Does
1. **Diagnostic Phase**: Runs comprehensive system checks
2. **Remediation Phase**: Optionally fixes identified issues (with user confirmation)
3. **Log Collection**: Gathers post-remediation system status and logs
4. **Structured Output**: Creates organized troubleshooting report

### Output File Structure
The integration creates `worker_node_join_scripts_output.txt` with these sections:
- **Section 1**: Diagnostic scan results
- **Section 2**: Remediation actions taken
- **Section 3**: Post-remediation system status and logs

## Manual Troubleshooting Steps

For users who prefer step-by-step control:

### Step 1: Run Diagnostics
```bash
sudo ./worker_node_join_diagnostics.sh
```
**Purpose**: Identifies CNI, kubelet, containerd, and filesystem issues

### Step 2: Run Remediation (if needed)
```bash
sudo ./worker_node_join_remediation.sh
```
**Purpose**: Fixes identified issues and prepares system for clean join

### Step 3: Generate Join Command (from control plane)
```bash
./generate_join_command.sh
```
**Purpose**: Creates fresh kubeadm join command with proper tokens

## Enhanced Cluster Deployment

### Automatic Log Collection
When deploying the cluster, logs are automatically collected:
```bash
./deploy.sh cluster
```

**Creates**: `deployment_logs_YYYYMMDD_HHMMSS.txt` containing:
- kubelet service logs (last 50 lines)
- containerd service logs (last 50 lines)  
- cluster status information
- node information

### Log Collection Details
- Runs in background during deployment
- Captures logs from last 5 minutes
- Includes cluster status if kubectl available
- Automatic on control plane nodes (192.168.4.63, 192.168.4.61, 192.168.4.62)

## Common Issues Resolved

### CNI Configuration Issues
- **Problem**: No network config found in /etc/cni/net.d
- **Detection**: Diagnostic script checks CNI directory and files
- **Resolution**: Remediation cleans CNI state for fresh configuration

### Kubelet Port Conflicts  
- **Problem**: Port 10250 in use by standalone kubelet
- **Detection**: Port scanning with netstat/ss
- **Resolution**: Proper service stop/mask/unmask sequence

### Containerd Filesystem Problems
- **Problem**: Invalid capacity 0 on image filesystem
- **Detection**: Filesystem capacity checks
- **Resolution**: Directory recreation and service restart

### Service State Issues
- **Problem**: Failed/inactive kubelet or containerd services
- **Detection**: systemctl status checks
- **Resolution**: Service enablement and restart procedures

## Troubleshooting Output Examples

### Successful Remediation
```
[SUCCESS] System prepared for kubeadm join!
[INFO] kubelet: inactive (enabled)
[INFO] containerd: active (enabled)  
[INFO] Port 10250: available
[INFO] CNI config: 0 files
[INFO] Containerd filesystem: 456G used: 6.9G
```

### Issue Detection
```
❌ CNI configuration missing: Look for 'CNI directory does not exist'
❌ Port 10250 conflicts: Look for kubelet processes using port 10250
❌ Filesystem capacity 0: Look for 0G, 0B in containerd checks
```

## File Structure

### Scripts
- `worker_node_troubleshoot_integration.sh` - Main integration script
- `worker_node_join_diagnostics.sh` - Diagnostic checks only
- `worker_node_join_remediation.sh` - Remediation actions only

### Output Files  
- `worker_node_join_scripts_output.txt` - Main troubleshooting session log
- `worker_node_join_scripts_output_template.txt` - Template for output structure
- `deployment_logs_*.txt` - Cluster deployment logs (auto-generated)

### Documentation
- `WORKER_NODE_TROUBLESHOOTING_GUIDE.md` - This guide
- `README.md` - Updated with enhanced workflow documentation

## Best Practices

1. **Always run diagnostics first** to understand the issues
2. **Review diagnostic output** before approving remediation
3. **Use integrated workflow** for comprehensive troubleshooting
4. **Keep output files** for future reference and analysis
5. **Check deployment logs** when cluster deployment issues occur

## Integration with Deploy.sh

The enhanced `deploy.sh` script automatically collects logs during cluster deployment:
- Runs log collection in background
- Creates timestamped log files
- Captures kubelet and containerd activity
- Includes cluster status information

This provides valuable debugging information when cluster deployment issues occur.

## Support and Validation

### Test Script
```bash
./test_worker_troubleshoot_integration.sh
```
Validates that all components are properly installed and configured.

### Manual Validation
```bash
# Check script availability
ls -la worker_node_*

# Check script permissions  
ls -la worker_node_troubleshoot_integration.sh

# Test script syntax
bash -n worker_node_troubleshoot_integration.sh
```