# VMStation Inter-Pod Communication Network Diagnosis

This document describes the automated network diagnosis system for troubleshooting inter-pod communication issues in the VMStation Kubernetes cluster.

## Overview

The network diagnosis playbook automates the comprehensive troubleshooting steps recommended by network experts for diagnosing CoreDNS, kube-proxy, and Flannel overlay network issues.

## Quick Start

### Option 1: Integrated with deploy.sh
```bash
# Run comprehensive network diagnosis
./deploy.sh diagnose
```

### Option 2: Direct script execution
```bash
# Run the diagnosis script directly
./scripts/run_network_diagnosis.sh

# With verbose output
./scripts/run_network_diagnosis.sh --verbose

# Check mode (no changes)
./scripts/run_network_diagnosis.sh --check
```

### Option 3: Direct Ansible playbook execution
```bash
# Run the diagnosis playbook
ansible-playbook -i ansible/inventory.txt ansible/plays/network-diagnosis.yaml

# With verbose output
ansible-playbook -i ansible/inventory.txt ansible/plays/network-diagnosis.yaml -vv
```

## What the Diagnosis Does

The playbook automates all the manual diagnosis steps from the problem statement:

### A. CoreDNS Pod Troubleshooting
- Collects CoreDNS pod status and configuration
- Retrieves CoreDNS logs (last 400 lines)
- Gathers detailed pod descriptions
- Collects recent events in kube-system namespace

### B. kube-proxy Investigation and Restart
- Identifies kube-proxy pods in CrashLoopBackOff state
- Collects logs from all kube-proxy pods
- **Automatically restarts** kube-proxy daemonset if issues detected
- Waits for pods to become ready after restart

### C. iptables NAT & POSTROUTING Verification
- Captures iptables NAT POSTROUTING rules on all nodes
- Captures KUBE-SERVICES chain configuration
- Filters for MASQUERADE and KUBE-* rules
- Checks kernel IP forwarding settings

### D. Flannel/VXLAN Traffic Capture and Analysis
- Captures VXLAN UDP port 8472 traffic during pod communication tests
- Analyzes network interface configuration (flannel.1, cni0)
- Generates test traffic between pods to trigger VXLAN encapsulation
- Provides detailed traffic analysis

### E. Flannel Logs & Configuration
- Collects Flannel pod logs
- Captures Flannel DaemonSet configuration
- Analyzes CNI plugin functionality

### F. DNS Testing
- Tests external DNS resolution (google.com)
- Tests internal DNS resolution (kubernetes.default)
- Performs pod-to-pod connectivity tests

## Output Structure

All diagnosis data is stored in timestamped directories:

```
ansible/artifacts/arc-network-diagnosis/
└── <timestamp>/
    ├── DIAGNOSIS-REPORT.md          # Comprehensive analysis report
    ├── diagnosis-summary.txt        # Quick summary
    ├── coredns-pods-info.yaml      # CoreDNS pod status
    ├── coredns-logs.txt            # CoreDNS logs
    ├── coredns-describe.txt        # Detailed pod descriptions
    ├── kube-proxy-pods-info.yaml   # kube-proxy status
    ├── kube-proxy-logs.txt         # kube-proxy logs
    ├── kube-system-events.yaml     # Recent kube-system events
    ├── flannel-logs-config.txt     # Flannel logs and config
    ├── dns-test-results.txt        # DNS test results
    ├── iptables-<hostname>.txt     # iptables rules per node
    ├── flannel-interfaces-<hostname>.txt  # network interfaces per node
    └── vxlan-analysis-<hostname>.txt      # VXLAN traffic analysis per node
```

## Automated Remediation

The playbook automatically performs these safe remediation steps:

1. **kube-proxy restart**: Rolling restart if CrashLoopBackOff detected
2. **Traffic generation**: Triggers VXLAN traffic for analysis
3. **Comprehensive logging**: Collects all relevant logs and configurations

## Manual Remediation Steps

After reviewing the diagnosis report, common next steps include:

### CoreDNS Issues
```bash
# Restart CoreDNS if API connectivity issues persist
kubectl rollout restart deployment/coredns -n kube-system

# Check service endpoints
kubectl get endpoints -n kube-system kube-dns

# Verify CoreDNS can reach API server
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
```

### DNS Resolution Issues
```bash
# Test DNS functionality
kubectl run --rm -i --tty testdns --image=busybox --restart=Never -- nslookup kubernetes.default

# Check DNS service configuration
kubectl get svc -n kube-system kube-dns
```

### VXLAN/Overlay Network Issues
```bash
# Check flannel pod status
kubectl get pods -n kube-flannel

# Restart flannel if needed
kubectl delete pods -n kube-flannel -l app=flannel

# Check for MTU issues
ip link show flannel.1  # Should show MTU 1450
```

### Switch/VLAN Issues (if no VXLAN traffic detected)
- Confirm switch ports are in correct VLANs or trunk mode
- Ensure switch allows UDP 8472 (VXLAN) traffic
- Check port-security/unknown-MAC blocking
- Verify MTU settings support VXLAN overhead

## Integration with Existing Scripts

The network diagnosis integrates with existing VMStation troubleshooting tools:

- Uses `kubectl` commands consistent with other scripts
- Follows the same logging and output patterns
- Stores artifacts in the standard `ansible/artifacts/` directory
- Can be triggered from the main `deploy.sh` script

## Prerequisites

- Ansible installed on the control node
- kubectl configured and accessible
- SSH access to all cluster nodes
- Appropriate permissions for iptables and tcpdump commands

## Troubleshooting the Diagnosis

If the diagnosis playbook itself fails:

```bash
# Check Ansible syntax
ansible-playbook ansible/plays/network-diagnosis.yaml --syntax-check

# Run in check mode
ansible-playbook -i ansible/inventory.txt ansible/plays/network-diagnosis.yaml --check

# Run with verbose output
ansible-playbook -i ansible/inventory.txt ansible/plays/network-diagnosis.yaml -vv
```

## Related Documentation

- [Inter-Pod Communication Troubleshooting](docs/fix_cluster_communication.md)
- [DNS Fix Guide](docs/dns-fix-guide.md)
- [CNI Bridge Fix](docs/CNI_BRIDGE_FIX.md)
- [CoreDNS Unknown Status Fix](docs/COREDNS_UNKNOWN_STATUS_FIX.md)