# VMStation Network Diagnosis Artifacts

This directory contains output from the automated network diagnosis playbook.

## Directory Structure

Each diagnosis run creates a timestamped subdirectory containing:

```
ansible/artifacts/arc-network-diagnosis/
├── <timestamp>/
│   ├── DIAGNOSIS-REPORT.md          # Comprehensive analysis report
│   ├── diagnosis-summary.txt        # Quick summary of the diagnosis
│   ├── coredns-pods-info.yaml      # CoreDNS pod status and configuration
│   ├── coredns-logs.txt            # CoreDNS pod logs
│   ├── coredns-describe.txt        # Detailed CoreDNS pod descriptions  
│   ├── kube-proxy-pods-info.yaml   # kube-proxy pod status
│   ├── kube-proxy-logs.txt         # kube-proxy pod logs
│   ├── kube-system-events.yaml     # Recent events in kube-system namespace
│   ├── flannel-logs-config.txt     # Flannel logs and configuration
│   ├── dns-test-results.txt        # DNS functionality test results
│   ├── iptables-<hostname>.txt     # iptables rules for each node
│   ├── flannel-interfaces-<hostname>.txt  # network interfaces for each node
│   └── vxlan-analysis-<hostname>.txt      # VXLAN traffic analysis for each node
```

## Usage

The network diagnosis playbook is automatically run when inter-pod communication issues are detected, or can be manually triggered:

```bash
# Run the complete network diagnosis
ansible-playbook -i ansible/inventory.txt ansible/plays/network-diagnosis.yaml

# Review the latest diagnosis
cd ansible/artifacts/arc-network-diagnosis/
ls -la | tail -1  # Get latest timestamp directory
cat <latest-timestamp>/DIAGNOSIS-REPORT.md
```

## Automatic Remediation

The playbook automatically performs these remediation steps:

1. **kube-proxy restart**: If CrashLoopBackOff pods are detected
2. **Log collection**: Comprehensive log gathering from all components
3. **Network testing**: Pod-to-pod and DNS connectivity tests
4. **Traffic capture**: VXLAN traffic analysis for overlay network issues

## Manual Remediation

After reviewing the diagnosis report, common manual steps include:

```bash
# Restart CoreDNS if still failing
kubectl rollout restart deployment/coredns -n kube-system

# Check service endpoints
kubectl get endpoints -n kube-system kube-dns

# Test DNS resolution
kubectl run --rm -i --tty testdns --image=busybox --restart=Never -- nslookup kubernetes.default
```

## Retention

Diagnosis artifacts are retained indefinitely for historical analysis. To clean up old diagnoses:

```bash
# Remove diagnoses older than 30 days
find ansible/artifacts/arc-network-diagnosis/ -name "[0-9]*" -type d -mtime +30 -exec rm -rf {} \;
```