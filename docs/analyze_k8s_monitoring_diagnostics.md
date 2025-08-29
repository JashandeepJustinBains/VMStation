# Kubernetes Monitoring Operations Assistant

## Overview
The `analyze_k8s_monitoring_diagnostics.sh` script is a Kubernetes operations assistant that analyzes monitoring cluster diagnostics and provides safe CLI remediation commands for specific Grafana and Loki issues. This tool follows strict operational rules and never executes commands directly - only provides CLI command output.

## Hard Rules
- **Never executes commands** - only outputs CLI remediation lines for human operators
- **Requires AUTO_APPROVE=yes** for destructive commands, otherwise only read-only inspection commands
- **Prefers safe, reversible actions** - shows dry-run helm commands before upgrades and suggests single-pod deletes

## Usage

```bash
# Safe mode (read-only commands only)
./scripts/analyze_k8s_monitoring_diagnostics.sh

# Include destructive commands (requires explicit confirmation)
./scripts/analyze_k8s_monitoring_diagnostics.sh AUTO_APPROVE=yes
```

Then paste your diagnostic output when prompted. Type `END` on a new line or press Ctrl+D when finished.

## Target Issues

The script specifically handles:

### Grafana Init Container Chown Issues
- Detects `chown: /var/lib/grafana/png: Permission denied` errors
- Provides exact `chown` command for operators to run on the host node
- Suggests safe pod recreation with proper selectors
- Handles hostPath PVC permission mismatches for Grafana UID 472:472

### Loki Configuration Parse Errors  
- Detects `field max_retries not found` config parse errors
- Creates minimal Helm values override files to fix invalid configuration
- Shows dry-run commands before any destructive operations
- Provides rollback options as safe fallbacks

## Expected Diagnostic Inputs

The operations assistant expects the following diagnostic outputs:

1. **Pod Status**: `kubectl -n monitoring get pods -o wide`
2. **Grafana Pod Details**: `kubectl -n monitoring describe pod <grafana_pod>`
3. **Grafana Init Container Logs**: `kubectl -n monitoring logs <grafana_pod> -c init-chown-data --tail=200`
4. **PVC Details**: `kubectl -n monitoring get pvc kube-prometheus-stack-grafana -o jsonpath='{.spec.volumeName}'`
5. **PV Configuration**: `kubectl get pv <PV_NAME> -o yaml`
6. **Loki Configuration**: `kubectl -n monitoring get secret loki-stack -o jsonpath='{.data.loki\.yaml}' | base64 -d`
7. **Helm Values**: `helm -n monitoring get values loki-stack --all`

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
1) Read-only verification commands (run these first):

   kubectl -n monitoring get pods -o wide
   kubectl -n monitoring describe pod <grafana_pod> -n monitoring
   kubectl -n monitoring logs <grafana_pod> -c init-chown-data --tail=200 || true
   kubectl -n monitoring get pvc kube-prometheus-stack-grafana -o jsonpath='{.spec.volumeName}{"\n"}'
   kubectl get pv <PV_NAME> -o yaml
   kubectl -n monitoring get secret loki-stack -o jsonpath='{.data.loki\.yaml}' | base64 -d | nl -ba | sed -n '1,240p'
   helm -n monitoring get values loki-stack --all

Concise diagnosis:
- Grafana init container failing due to hostPath permission mismatch (chown denied for UID 472:472)
- Loki CrashLoopBackOff due to config parse error (invalid max_retries field on line 33)

2) Grafana hostPath ownership mismatch remediation:

OPERATOR-RUN: sudo chown -R 472:472 /var/lib/kubernetes/local-path-provisioner/pvc-480b2659-d6de-4256-941b-45c8c07559ce_monitoring_kube-prometheus-stack-grafana
(Operator must run this as root on the node that hosts the PV)

For destructive pod recreation commands, re-run with AUTO_APPROVE=yes

3) Loki config parse error remediation:

Option Fix (preferred): Create minimal values override file that removes invalid max_retries key:

First, create loki-fix-values.yaml:
cat > loki-fix-values.yaml << 'EOF'
loki:
  config:
    table_manager:
      # Remove max_retries field - not valid in this context
      retention_deletes_enabled: true
      retention_period: 168h
EOF

Then show dry-run first:
   helm -n monitoring upgrade --reuse-values loki-stack grafana/loki-stack -f loki-fix-values.yaml --dry-run

For destructive helm upgrade commands, re-run with AUTO_APPROVE=yes
```

## Integration with VMStation

This analyzer complements the existing VMStation monitoring diagnostic tools:

- `diagnose_monitoring_permissions.sh` - File permission and SELinux analysis
- `validate_k8s_monitoring.sh` - Comprehensive monitoring stack validation
- `fix_monitoring_permissions.sh` - Automated permission fixes
- `get_copilot_prompt.sh` - Premium Copilot agent prompt for comprehensive troubleshooting

For complex multi-component issues requiring broader analysis, use the premium Copilot prompt:
```bash
./scripts/get_copilot_prompt.sh --show
```

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