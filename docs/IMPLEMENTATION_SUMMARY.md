# Premium Copilot K8s Monitoring Prompt - Implementation Summary

## Requirements Fulfillment

This implementation addresses all requirements from the problem statement:

### ✅ Provide a ready-to-use prompt for the premium Copilot agent
- **Template File**: `docs/premium_copilot_k8s_monitoring_prompt.md`
- **Complete File**: `docs/premium_copilot_k8s_monitoring_complete_prompt.md`
- **Access**: `./scripts/get_copilot_prompt.sh --show` (template) or `--complete` (ready-to-use)
- **Status**: Complete and ready for copy-paste

The implementation now provides two options:
1. **Template prompt** - Requires separate diagnostic gathering
2. **Complete prompt** - Includes embedded diagnostic output for immediate use

### ✅ Instruct agent to not change file permissions or create directories itself
- **Implementation**: Clear constraints section in prompt
- **Key text**: "Do NOT modify file permissions, create directories, or make changes automatically"
- **Approach**: Commands marked as "operator-run suggestions" only

### ✅ Ask agent to produce CLI commands the operator can run to fix issues
- **Implementation**: Prompt explicitly requests "exact shell/cli commands I should run"
- **Format**: All commands copy-paste ready with explanations
- **Safety**: Destructive commands clearly marked and require confirmation

### ✅ Ensure agent uses the correct hostnames when referencing nodes
- **Hostnames specified**: 
  - masternode — 192.168.4.63
  - storagenodet3500 — 192.168.4.61
  - localhost.localdomain — 192.168.4.62
- **Enforcement**: "use these hostnames/IPs exactly when referencing nodes"

### ✅ Include gathered diagnostics in the prompt
- **Implementation**: Complete prompt file with embedded cluster snapshot
- **File**: `docs/premium_copilot_k8s_monitoring_complete_prompt.md`
- **Access**: `./scripts/get_copilot_prompt.sh --complete`
- **Diagnostics included**: Node status, pod states, events, PVCs from actual cluster
### ✅ Prioritize likely root causes and give verification commands
- **Root causes covered**:
  - Init-container chown issues
  - hostPath permissions  
  - PVC/PV binding issues
  - RBAC/serviceaccount failures
  - Missing configmaps/secrets
  - Container image errors
  - Readiness/liveness probe misconfiguration
- **Verification**: Each diagnostic includes expected good vs bad output

## Key Implementation Features

### 1. Comprehensive Diagnostic Structure
The prompt requests 10 specific diagnostic areas:
1. Quick triage checklist
2. Per-failing-pod diagnostic recipe
3. RBAC & ServiceAccount checks
4. Storage/PV/PVC checks
5. Config/Manifest issues
6. Init-container specific checks
7. Node runtime logs
8. Minimal ansible "check-only" tasks
9. Verification & smoke tests
10. Concise prioritized action plan

### 2. Safety-First Approach
- Never executes commands automatically
- Clear marking of operator-only commands
- Step-by-step verification requirements
- Minimal, surgical fixes preferred
- Idempotent checks prioritized

### 3. VMStation Integration
- Proper hostname awareness for the specific environment
- Integration with existing diagnostic tools
- Cross-references to focused analysis scripts
- Maintains repository's safety principles

### 4. Ease of Use
- Simple script access: `./scripts/get_copilot_prompt.sh`
- Clipboard copy functionality (when available)
- Basic diagnostic gathering: `--gather` option
- Clear usage instructions and examples

## Usage Workflow

### Template Prompt (Traditional)
1. **Access the template**: `./scripts/get_copilot_prompt.sh --show`
2. **Copy to premium Copilot agent**
3. **Gather diagnostics**: `./scripts/get_copilot_prompt.sh --gather`
4. **Provide cluster output to agent**
5. **Follow agent's step-by-step remediation plan**
6. **Verify each fix with provided commands**

### Complete Prompt (Ready-to-Use)
1. **Access the complete prompt**: `./scripts/get_copilot_prompt.sh --complete`
2. **Copy directly to premium Copilot agent** (no additional diagnostics needed)
3. **Follow agent's step-by-step remediation plan**
4. **Verify each fix with provided commands**

## Integration Points

### With Existing Tools
- **analyze_k8s_monitoring_diagnostics.sh**: Focused Grafana/Loki analysis
- **validate_k8s_monitoring.sh**: Comprehensive validation
- **diagnose_monitoring_permissions.sh**: Permission-specific diagnostics

### Documentation Updates
- **README.md**: Added troubleshooting section
- **MODULAR_PLAYBOOK_GUIDE.md**: Enhanced monitoring scripts inventory
- **analyze_k8s_monitoring_diagnostics.md**: Cross-reference to premium prompt

## Expected Output Quality

The premium Copilot agent will provide:
- **Immediate triage**: Safe read-only commands first
- **Detailed analysis**: Pod-specific remediation steps
- **Host-aware fixes**: Commands using correct VMStation hostnames
- **Verification steps**: Confirmation commands for each fix
- **Prevention advice**: Recommended configuration changes

This implementation provides a production-ready troubleshooting solution that maintains VMStation's strict safety standards while delivering expert-level diagnostic guidance.