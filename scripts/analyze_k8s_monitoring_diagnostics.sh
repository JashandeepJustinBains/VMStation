#!/bin/bash

# Kubernetes Monitoring Operations Assistant
# Analyzes Kubernetes cluster diagnostics and provides safe CLI remediation commands
# 
# Hard Rules:
# - Never modify host files, change permissions, or execute commands yourself. Only output CLI remediation lines.
# - Always require explicit AUTO_APPROVE=yes flag for destructive commands. Otherwise only read-only inspection commands.
# - Always prefer safe, reversible actions: show dry-run helm commands before upgrades and suggest single-pod deletes.
#
# Usage: ./analyze_k8s_monitoring_diagnostics.sh [AUTO_APPROVE=yes]

set -e

echo "=== Kubernetes Operations Assistant ==="
echo "Timestamp: $(date)"
echo ""

# Check for AUTO_APPROVE flag
AUTO_APPROVE="${AUTO_APPROVE:-no}"
if [[ "$1" == "AUTO_APPROVE=yes" ]] || [[ "$AUTO_APPROVE" == "yes" ]]; then
    AUTO_APPROVE="yes"
    echo "⚠️  AUTO_APPROVE=yes detected - destructive commands will be included in output"
    echo ""
else
    echo "ℹ️  Running in safe mode - only read-only commands will be provided"
    echo "   Use AUTO_APPROVE=yes to include destructive commands"
    echo ""
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables for analysis
declare -a READONLY_COMMANDS=()
declare -a GRAFANA_ISSUES=()
declare -a LOKI_ISSUES=()
declare -a DESTRUCTIVE_COMMANDS=()

# Function to add read-only diagnostic commands
add_readonly_command() {
    local command="$1"
    READONLY_COMMANDS+=("$command")
}

# Function to add destructive command (only shown if AUTO_APPROVE=yes)
add_destructive_command() {
    local command="$1"
    local justification="$2"
    DESTRUCTIVE_COMMANDS+=("$command|$justification")
}

# Function to detect Grafana init container chown issues
analyze_grafana_chown_issues() {
    local input="$1"
    
    echo "Analyzing for Grafana init container chown permission issues..."
    
    # Check for Grafana chown permission denied errors
    if echo "$input" | grep -q "chown.*Permission denied" && echo "$input" | grep -q "grafana"; then
        GRAFANA_ISSUES+=("Grafana init container chown permission denied")
        
        # Extract PVC name and expected UID if mentioned
        local pvc_info=$(echo "$input" | grep -o "pvc-[a-f0-9-]*_monitoring_[^[:space:]]*" | head -1)
        local expected_uid="472:472"  # Standard Grafana UID:GID
        
        if [[ -n "$pvc_info" ]]; then
            echo "  → Detected PVC path issue: $pvc_info"
            echo "  → Expected Grafana UID:GID: $expected_uid"
        fi
    fi
    
    # Check for Init:CrashLoopBackOff on Grafana pods
    if echo "$input" | grep -q "Init:CrashLoopBackOff" && echo "$input" | grep -q "grafana"; then
        GRAFANA_ISSUES+=("Grafana pods in Init:CrashLoopBackOff state")
    fi
}

# Function to detect Loki config parse errors
analyze_loki_config_issues() {
    local input="$1"
    
    echo "Analyzing for Loki configuration parse errors..."
    
    # Check for Loki max_retries config error
    if echo "$input" | grep -q "field max_retries not found" && echo "$input" | grep -q "loki"; then
        LOKI_ISSUES+=("Loki config parse error: max_retries field not found")
        echo "  → Detected Loki YAML config error on line 33: max_retries field not found"
    fi
    
    # Check for Loki CrashLoopBackOff
    if echo "$input" | grep -q "CrashLoopBackOff" && echo "$input" | grep -q "loki"; then
        LOKI_ISSUES+=("Loki pods in CrashLoopBackOff state")
    fi
}

# Function to generate read-only verification commands (Task 1)
generate_readonly_commands() {
    echo "1) Read-only verification commands (run these first):"
    echo ""
    
    # Always output these read-only commands first as specified
    add_readonly_command "kubectl -n monitoring get pods -o wide"
    add_readonly_command "kubectl -n monitoring describe pod <grafana_pod> -n monitoring"
    add_readonly_command "kubectl -n monitoring logs <grafana_pod> -c init-chown-data --tail=200 || true"
    add_readonly_command "kubectl -n monitoring get pvc kube-prometheus-stack-grafana -o jsonpath='{.spec.volumeName}{\"\n\"}'"
    add_readonly_command "kubectl get pv <PV_NAME> -o yaml"
    add_readonly_command "kubectl -n monitoring get secret loki-stack -o jsonpath='{.data.loki\.yaml}' | base64 -d | nl -ba | sed -n '1,240p'"
    add_readonly_command "helm -n monitoring get values loki-stack --all"
    
    for cmd in "${READONLY_COMMANDS[@]}"; do
        echo "   $cmd"
    done
    echo ""
}

# Function to generate Grafana remediation commands (Task 2)
generate_grafana_remediation() {
    if [[ ${#GRAFANA_ISSUES[@]} -eq 0 ]]; then
        return
    fi
    
    echo "2) Grafana hostPath ownership mismatch remediation:"
    echo ""
    
    # Always show the chown command that operator must run
    echo "OPERATOR-RUN: sudo chown -R 472:472 /var/lib/kubernetes/local-path-provisioner/pvc-480b2659-d6de-4256-941b-45c8c07559ce_monitoring_kube-prometheus-stack-grafana"
    echo "(Operator must run this as root on the node that hosts the PV)"
    echo ""
    
    # Only show destructive commands if AUTO_APPROVE=yes
    if [[ "$AUTO_APPROVE" == "yes" ]]; then
        echo "Safe pod-recreate command (AUTO_APPROVE=yes provided):"
        echo "   kubectl -n monitoring delete pod -l app.kubernetes.io/name=grafana,app.kubernetes.io/instance=kube-prometheus-stack"
        echo ""
        echo "Non-destructive watch command:"
        echo "   kubectl -n monitoring get pods -w"
        echo ""
    else
        echo "For destructive pod recreation commands, re-run with AUTO_APPROVE=yes"
        echo ""
    fi
}

# Function to generate Loki remediation commands (Task 3)
generate_loki_remediation() {
    if [[ ${#LOKI_ISSUES[@]} -eq 0 ]]; then
        return
    fi
    
    echo "3) Loki config parse error remediation:"
    echo ""
    
    echo "Option Fix (preferred): Create minimal values override file that removes invalid max_retries key:"
    echo ""
    echo "First, create loki-fix-values.yaml:"
    echo "cat > loki-fix-values.yaml << 'EOF'"
    echo "loki:"
    echo "  config:"
    echo "    table_manager:"
    echo "      # Remove max_retries field - not valid in this context"
    echo "      retention_deletes_enabled: true"
    echo "      retention_period: 168h"
    echo "EOF"
    echo ""
    
    echo "Then show dry-run first:"
    echo "   helm -n monitoring upgrade --reuse-values loki-stack grafana/loki-stack -f loki-fix-values.yaml --dry-run"
    echo ""
    
    if [[ "$AUTO_APPROVE" == "yes" ]]; then
        echo "Actual upgrade command (AUTO_APPROVE=yes provided):"
        echo "   helm -n monitoring upgrade --reuse-values loki-stack grafana/loki-stack -f loki-fix-values.yaml"
        echo ""
        echo "Option Quick fallback (if operator requests):"
        echo "   helm -n monitoring rollback loki-stack <REVISION>"
        echo ""
    else
        echo "For destructive helm upgrade commands, re-run with AUTO_APPROVE=yes"
        echo ""
    fi
}

# Function to generate verification commands (Task 4)
generate_verification_commands() {
    echo "4) Safety and verification commands (run after any chown or helm upgrade):"
    echo ""
    echo "   kubectl -n monitoring get pods -o wide"
    echo "   kubectl -n monitoring logs loki-stack-0 -c loki --tail=200 || kubectl -n monitoring logs loki-stack-0 --tail=200"
    echo "   kubectl -n monitoring logs <grafana_pod> -c init-chown-data --tail=200 || true"
    echo ""
}

# Function to provide diagnosis based on detected issues
generate_diagnosis() {
    echo "Concise diagnosis:"
    
    local diagnosis_lines=()
    
    if [[ ${#GRAFANA_ISSUES[@]} -gt 0 ]]; then
        diagnosis_lines+=("- Grafana init container failing due to hostPath permission mismatch (chown denied for UID 472:472)")
    fi
    
    if [[ ${#LOKI_ISSUES[@]} -gt 0 ]]; then
        diagnosis_lines+=("- Loki CrashLoopBackOff due to config parse error (invalid max_retries field on line 33)")
    fi
    
    if [[ ${#diagnosis_lines[@]} -eq 0 ]]; then
        echo "- No critical Grafana chown or Loki config issues detected in provided input"
    else
        for line in "${diagnosis_lines[@]}"; do
            echo "$line"
        done
    fi
    echo ""
}

# Main analysis function
perform_analysis() {
    local input="$1"
    
    echo "=== ANALYSIS IN PROGRESS ==="
    echo ""
    
    # Analyze for specific issues mentioned in the problem statement
    analyze_grafana_chown_issues "$input"
    analyze_loki_config_issues "$input"
    
    echo "Analysis complete."
    echo ""
    
    # Generate output in the required format
    generate_readonly_commands
    generate_diagnosis
    generate_grafana_remediation  
    generate_loki_remediation
    generate_verification_commands
    
    # Final instruction as specified
    echo ""
    echo "Run the read-only commands above and paste the grafana init-chown logs and the loki yaml snippet around 'max_retries' (8–12 lines) and I will produce the exact one-line remediation commands (chown + pod-delete or helm override + dry-run)."
}

# Main function to prompt for input and analyze
main() {
    echo "This operations assistant analyzes Kubernetes monitoring diagnostics for specific Grafana and Loki issues."
    echo ""
    echo "Context (from operator paste):"
    echo "- Grafana init container failing with chown errors: chown: /var/lib/grafana/png: Permission denied"
    echo "- PVC -> PV hostPath: /var/lib/kubernetes/local-path-provisioner/pvc-480b2659-d6de-4256-941b-45c8c07559ce_monitoring_kube-prometheus-stack-grafana"
    echo "- Grafana expected UID:GID: 472:472 (common grafana UID)"
    echo "- Grafana pods are stuck in Init:CrashLoopBackOff"
    echo "- Loki CrashLoopBackOff with config parse error: failed parsing config: /etc/loki/loki.yaml: yaml: unmarshal errors: line 33: field max_retries not found in type validation.plain"
    echo ""
    echo "Please provide your diagnostic output by pasting it below."
    echo "Expected inputs:"
    echo "- kubectl -n monitoring get pods -o wide"
    echo "- kubectl -n monitoring describe pod <grafana_pod>"
    echo "- kubectl -n monitoring logs <grafana_pod> -c init-chown-data"
    echo "- kubectl -n monitoring get secret loki-stack -o jsonpath='{.data.loki\.yaml}' | base64 -d"
    echo ""
    echo "Press Ctrl+D when finished, or type 'END' on a new line:"
    echo ""
    
    # Read all input until EOF
    local input=""
    while IFS= read -r line; do
        if [ "$line" = "END" ]; then
            break
        fi
        input="$input$line"$'\n'
    done
    
    if [ -z "$input" ]; then
        echo "No input provided. Providing standard remediation commands based on described context."
        echo ""
        # Use a synthetic input that matches the described issues
        input="Init:CrashLoopBackOff grafana chown: /var/lib/grafana/png: Permission denied field max_retries not found loki CrashLoopBackOff"
    fi
    
    # Perform the analysis
    perform_analysis "$input"
}

# Run main function
main "$@"