# Kubernetes Monitoring Diagnostics Analyzer

## Overview
The `analyze_k8s_monitoring_diagnostics.sh` script analyzes Kubernetes monitoring stack diagnostics and provides safe CLI commands to fix common issues. This tool follows strict non-destructive principles and only provides analysis and remediation commands - it never executes commands directly.

## Usage

```bash
./scripts/analyze_k8s_monitoring_diagnostics.sh
```

Then paste your diagnostic output when prompted. Type `END` on a new line or press Ctrl+D when finished.

## Supported Diagnostic Inputs

The analyzer accepts the following types of diagnostic output:

1. **Node Status**: `kubectl get nodes -o wide`
2. **Pod Status**: `kubectl -n monitoring get pods -o wide`
3. **Pending Pods**: `kubectl -n monitoring get pods --field-selector=status.phase=Pending -o wide`
4. **Events**: `kubectl -n monitoring get events --sort-by=.metadata.creationTimestamp`
5. **Secrets/ConfigMaps**: `kubectl -n monitoring get secret,configmap --show-labels`
6. **Helm Status**: `helm -n monitoring ls --all` and `helm -n monitoring status <release>`
7. **Operator Logs**: `kubectl -n monitoring logs <operator-pod> --tail=300`

## Analysis Capabilities

The tool detects and provides remediation for:

- **Missing Secrets/ConfigMaps**: Operator-generated resources not being created
- **Volume Mount Failures**: Missing resources causing pod startup failures
- **Pod Scheduling Issues**: Node affinity, taints, and tolerations problems
- **Init Container Failures**: CrashLoopBackOff states in init containers
- **Operator Reconciliation Errors**: Prometheus operator not creating resources
- **Helm Release Issues**: Failed or stuck deployments

## Output Format

The analyzer provides:

1. **One-line summary** of the primary cause
2. **Additional diagnostics** needed (if any)
3. **Numbered list of safe CLI commands** with:
   - Intent description
   - Read-only command
   - Verification command
4. **Destructive actions** (if needed) requiring explicit confirmation

## Safety Features

- **Never executes commands** - only provides recommendations
- **Read-only diagnostics first** - always suggests inspection before action
- **Explicit confirmation required** for destructive actions (requires `CONFIRM` or `AUTO_APPROVE=true`)
- **Safety checks** before any command that modifies cluster state
- **Verification commands** for every remediation step

## Example Output

```
1) Missing secrets/configmaps causing volume mount failures and init container crashes

2) Additional diagnostics needed:
```bash
kubectl -n monitoring logs -l app.kubernetes.io/name=prometheus-operator --tail=50
```

3) Safe remediation commands:

1. Intent: Check missing secrets and configmaps
```bash
kubectl -n monitoring get secret,configmap --show-labels
# intent: Check missing secrets and configmaps; safe, read-only
```

Verification:
```bash
kubectl -n monitoring describe pods | grep -A5 -B5 'FailedMount'
```

4) Destructive actions (requires explicit CONFIRM or AUTO_APPROVE=true):

Intent: Copy kube-root-ca.crt configmap to monitoring namespace
Safety check: This command modifies cluster state

```bash
# SAFETY: Verify impact before running - requires CONFIRM
kubectl get configmap kube-root-ca.crt -n kube-system -o yaml > /tmp/kube-root-ca.yaml && sed -i 's/namespace: kube-system/namespace: monitoring/' /tmp/kube-root-ca.yaml && kubectl apply -f /tmp/kube-root-ca.yaml
```
```

## Integration with VMStation

This analyzer complements the existing VMStation monitoring diagnostic tools:

- `diagnose_monitoring_permissions.sh` - File permission and SELinux analysis
- `validate_k8s_monitoring.sh` - Comprehensive monitoring stack validation
- `fix_monitoring_permissions.sh` - Automated permission fixes

## Rules and Constraints

The analyzer follows VMStation's strict operational rules:

- ✅ Never runs Ansible or automated changes
- ✅ Never changes host file permissions/ownership
- ✅ Never executes commands directly
- ✅ Provides only text output with analysis and CLI commands
- ✅ Includes safety checks for destructive commands
- ✅ Requires explicit confirmation for modifications
- ✅ Prefers non-destructive fixes first

## Common Issues Detected

### Missing Secrets/ConfigMaps
- `alertmanager-kube-prometheus-stack-alertmanager-generated` not created by operator
- `prometheus-kube-prometheus-stack-prometheus` configuration missing
- `kube-root-ca.crt` not available in monitoring namespace
- `loki-stack-promtail` configuration missing

### Scheduling Problems
- Control plane taints preventing pod scheduling
- Node affinity mismatches
- Missing tolerations for tainted nodes

### Operator Issues
- Prometheus operator not reconciling resources
- RBAC permission problems
- Missing CRDs or API resources

### Init Container Failures
- Configuration dependencies not available
- Mount path issues
- Startup probe failures