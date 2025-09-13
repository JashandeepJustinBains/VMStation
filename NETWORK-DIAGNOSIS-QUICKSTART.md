# VMStation Network Diagnosis - Quick Start Guide

## Problem Statement Addressed

This automated solution addresses the inter-pod communication issues described in the problem statement where:
- CoreDNS pods fail with "dial tcp 10.96.0.1:443: connect: no route to host"
- kube-proxy pods are in CrashLoopBackOff state
- Pod networking is broken preventing DNS resolution

## Quick Usage

### Option 1: Integrated Command (Recommended)
```bash
# Run complete network diagnosis from deploy.sh
./deploy.sh diagnose
```

### Option 2: Direct Script Execution
```bash
# Run with helper script
./scripts/run_network_diagnosis.sh

# With verbose output
./scripts/run_network_diagnosis.sh --verbose

# Check mode (safe, no changes)
./scripts/run_network_diagnosis.sh --check
```

### Option 3: Direct Ansible Execution
```bash
# Run the playbook directly
ansible-playbook -i ansible/inventory.txt ansible/plays/network-diagnosis.yaml
```

## What Gets Automated

The solution automates all the manual commands from the problem statement:

### A. CoreDNS Troubleshooting
- Automatically runs: `kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide`
- Automatically runs: `kubectl describe deployment coredns -n kube-system`
- Automatically collects CoreDNS logs and events

### B. kube-proxy Investigation & Restart
- Automatically detects CrashLoopBackOff kube-proxy pods
- **Automatically restarts** kube-proxy daemonset with: `kubectl rollout restart daemonset/kube-proxy -n kube-system`
- Waits for pods to become ready

### C. iptables Verification
- Automatically runs: `sudo iptables -t nat -L POSTROUTING -n -v` on all nodes
- Automatically runs: `sudo iptables -t nat -L KUBE-SERVICES -n -v` on all nodes
- Checks kernel forwarding settings

### D. VXLAN Traffic Capture
- Automatically captures VXLAN traffic during pod communication tests
- Runs: `sudo timeout 15 tcpdump -nni enp2s0 udp port 8472 -c 100`
- Generates test traffic between pods

### E. Flannel Diagnostics
- Automatically runs: `kubectl -n kube-system logs ds/kube-flannel --tail=200`
- Collects flannel configuration

### F. DNS Testing
- Automatically runs: `kubectl run --rm -i --tty testns --image=busybox --restart=Never -- nslookup google.com`
- Tests internal DNS resolution

## Output Structure

All diagnosis data is stored in timestamped directories:

```
ansible/artifacts/arc-network-diagnosis/
└── <timestamp>/
    ├── DIAGNOSIS-REPORT.md          # Comprehensive analysis
    ├── coredns-logs.txt            # CoreDNS issues and logs
    ├── kube-proxy-logs.txt         # kube-proxy crash details
    ├── iptables-<hostname>.txt     # NAT rules per node
    ├── vxlan-analysis-<hostname>.txt # VXLAN traffic analysis
    ├── flannel-logs-config.txt     # Flannel configuration
    └── dns-test-results.txt        # DNS functionality tests
```

## Expected Results

After running the diagnosis:

1. **Immediate**: kube-proxy will be restarted if in CrashLoopBackOff
2. **Analysis**: Comprehensive report identifies root causes
3. **Remediation**: Specific commands provided for manual fixes
4. **Verification**: DNS and pod connectivity tests show current status

## Next Steps After Diagnosis

The system provides specific remediation commands based on findings:

```bash
# If CoreDNS still has API connectivity issues:
kubectl rollout restart deployment/coredns -n kube-system

# If DNS resolution still fails:
kubectl get endpoints -n kube-system kube-dns

# If VXLAN traffic shows no packets:
# Check switch/VLAN configuration (see diagnosis report)
```

## Integration with Existing VMStation Tools

The network diagnosis integrates with existing VMStation scripts:
- Uses same inventory and configuration files
- Follows VMStation logging patterns
- Stores artifacts in standard locations
- Can be called from main deployment script

This provides a complete, automated solution for the inter-pod communication issues described in the problem statement.