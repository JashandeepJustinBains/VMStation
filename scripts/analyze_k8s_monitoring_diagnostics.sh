#!/bin/bash

# Kubernetes Monitoring Diagnostics Analyzer
# Analyzes pasted diagnostic output and provides safe CLI commands to fix issues
# 
# Usage: ./analyze_k8s_monitoring_diagnostics.sh
# Then paste your diagnostic output when prompted

set -e

echo "=== VMStation K8s Monitoring Diagnostics Analyzer ==="
echo "Timestamp: $(date)"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables for analysis
declare -a ISSUES=()
declare -a COMMANDS=()
declare -a DESTRUCTIVE_COMMANDS=()

# Function to add a diagnostic command
add_command() {
    local intent="$1"
    local command="$2"
    local verification="$3"
    local destructive="${4:-false}"
    
    if [ "$destructive" = "true" ]; then
        DESTRUCTIVE_COMMANDS+=("$intent|$command|$verification")
    else
        COMMANDS+=("$intent|$command|$verification")
    fi
}

# Function to analyze node status
analyze_nodes() {
    local input="$1"
    
    echo "Analyzing node status..."
    
    # Check for NotReady nodes
    if echo "$input" | grep -q "NotReady"; then
        ISSUES+=("NotReady nodes detected")
        add_command "Check node status details" \
                   "kubectl describe nodes" \
                   "kubectl get nodes -o wide"
    fi
    
    # Check for taints that might affect scheduling
    if echo "$input" | grep -q "node-role.kubernetes.io/control-plane"; then
        ISSUES+=("Control plane taints affecting pod scheduling")
        add_command "Check node taints" \
                   "kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints" \
                   "kubectl get nodes -o wide"
    fi
}

# Function to analyze pod status
analyze_pods() {
    local input="$1"
    
    echo "Analyzing pod status..."
    
    # Check for CrashLoopBackOff
    if echo "$input" | grep -q "CrashLoopBackOff"; then
        ISSUES+=("Pods in CrashLoopBackOff state")
        local failed_pods=$(echo "$input" | grep "CrashLoopBackOff" | awk '{print $1}')
        for pod in $failed_pods; do
            add_command "Check logs for $pod" \
                       "kubectl -n monitoring logs $pod --previous" \
                       "kubectl -n monitoring get pod $pod -o yaml"
            add_command "Describe $pod for detailed events" \
                       "kubectl -n monitoring describe pod $pod" \
                       "kubectl -n monitoring get events --field-selector involvedObject.name=$pod"
        done
    fi
    
    # Check for Init:CrashLoopBackOff specifically
    if echo "$input" | grep -q "Init:CrashLoopBackOff"; then
        ISSUES+=("Init containers failing")
        add_command "Check init container logs" \
                   "kubectl -n monitoring logs <pod-name> -c <init-container-name> --previous" \
                   "kubectl -n monitoring describe pod <pod-name>"
    fi
    
    # Check for Pending pods
    if echo "$input" | grep -q "Pending"; then
        ISSUES+=("Pods stuck in Pending state")
        add_command "Analyze pending pod scheduling" \
                   "kubectl -n monitoring get pods --field-selector=status.phase=Pending -o wide" \
                   "kubectl -n monitoring describe pods --field-selector=status.phase=Pending"
    fi
}

# Function to analyze events
analyze_events() {
    local input="$1"
    
    echo "Analyzing Kubernetes events..."
    
    # Check for FailedMount errors
    if echo "$input" | grep -q "FailedMount"; then
        ISSUES+=("Volume mount failures detected")
        add_command "Check missing secrets and configmaps" \
                   "kubectl -n monitoring get secret,configmap --show-labels" \
                   "kubectl -n monitoring describe pods | grep -A5 -B5 'FailedMount'"
        
        # Check for specific missing objects
        if echo "$input" | grep -q '"monitoring"/"kube-root-ca.crt" not registered'; then
            add_command "Copy kube-root-ca.crt configmap to monitoring namespace" \
                       "kubectl get configmap kube-root-ca.crt -n kube-system -o yaml > /tmp/kube-root-ca.yaml && sed -i 's/namespace: kube-system/namespace: monitoring/' /tmp/kube-root-ca.yaml && kubectl apply -f /tmp/kube-root-ca.yaml" \
                       "kubectl -n monitoring get configmap kube-root-ca.crt" \
                       "true"
        fi
        
        if echo "$input" | grep -q 'alertmanager-kube-prometheus-stack-alertmanager-generated.*not registered'; then
            add_command "Wait for AlertManager operator reconciliation" \
                       "kubectl -n monitoring get alertmanager -w --timeout=120s" \
                       "kubectl -n monitoring get secret | grep alertmanager"
        fi
        
        if echo "$input" | grep -q 'prometheus-kube-prometheus-stack-prometheus.*not registered'; then
            add_command "Wait for Prometheus operator reconciliation" \
                       "kubectl -n monitoring get prometheus -w --timeout=120s" \
                       "kubectl -n monitoring get configmap | grep prometheus"
        fi
    fi
    
    # Check for FailedScheduling
    if echo "$input" | grep -q "FailedScheduling"; then
        ISSUES+=("Pod scheduling failures")
        
        # Check for node affinity issues
        if echo "$input" | grep -q "didn't match Pod's node affinity"; then
            add_command "Check pod node affinity requirements" \
                       "kubectl -n monitoring get pods -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.spec.affinity}{\"\\n\"}{end}'" \
                       "kubectl get nodes --show-labels"
        fi
        
        # Check for taint issues - be more specific about the fix
        if echo "$input" | grep -q "untolerated taint.*node-role.kubernetes.io/control-plane"; then
            add_command "Check which pods need control plane tolerations" \
                       "kubectl -n monitoring get pods -o jsonpath='{range .items[*]}{.metadata.name}{\"\\t\"}{.spec.tolerations}{\"\\n\"}{end}'" \
                       "kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints"
            add_command "Add tolerations to Grafana deployment for control plane scheduling" \
                       "kubectl -n monitoring patch deployment kube-prometheus-stack-grafana -p '{\"spec\":{\"template\":{\"spec\":{\"tolerations\":[{\"key\":\"node-role.kubernetes.io/control-plane\",\"operator\":\"Exists\",\"effect\":\"NoSchedule\"}]}}}}'" \
                       "kubectl -n monitoring get pods -l app.kubernetes.io/name=grafana" \
                       "true"
        fi
        
        if echo "$input" | grep -q "untolerated taint.*unreachable"; then
            add_command "Check node readiness status" \
                       "kubectl get nodes -o wide" \
                       "kubectl describe nodes | grep -A10 -B5 'Taints\\|Conditions'"
        fi
    fi
}

# Function to analyze secrets and configmaps
analyze_secrets_configmaps() {
    local input="$1"
    
    echo "Analyzing secrets and configmaps..."
    
    # Check for operator-generated resources that should exist
    if ! echo "$input" | grep -q "alertmanager-kube-prometheus-stack-alertmanager-generated"; then
        ISSUES+=("Missing operator-generated secret: alertmanager-kube-prometheus-stack-alertmanager-generated")
        add_command "Check if AlertManager CRD exists and is being reconciled" \
                   "kubectl -n monitoring get alertmanager" \
                   "kubectl -n monitoring describe alertmanager"
        add_command "Wait for operator to reconcile resources (may take 2-3 minutes)" \
                   "kubectl -n monitoring get alertmanager -w --timeout=180s" \
                   "kubectl -n monitoring get secret | grep alertmanager"
    fi
    
    if ! echo "$input" | grep -q "prometheus-kube-prometheus-stack-prometheus"; then
        ISSUES+=("Missing operator-generated configmap: prometheus-kube-prometheus-stack-prometheus")
        add_command "Check if Prometheus CRD exists and is being reconciled" \
                   "kubectl -n monitoring get prometheus" \
                   "kubectl -n monitoring describe prometheus"
        add_command "Check for PrometheusRule resources that should generate config" \
                   "kubectl -n monitoring get prometheusrule" \
                   "kubectl -n monitoring describe prometheusrule"
    fi
    
    if ! echo "$input" | grep -q "loki-stack-promtail"; then
        ISSUES+=("Missing configmap: loki-stack-promtail")
        add_command "Check if Loki stack Helm release exists" \
                   "helm -n monitoring ls | grep loki" \
                   "helm -n monitoring status loki-stack"
        add_command "Verify Loki stack deployment" \
                   "kubectl -n monitoring get statefulset,daemonset | grep loki" \
                   "kubectl -n monitoring describe daemonset loki-stack-promtail"
    fi
    
    # Check for the critical kube-root-ca.crt configmap
    if echo "$input" | grep -q '"kube-root-ca.crt" not registered'; then
        ISSUES+=("Critical: kube-root-ca.crt configmap mount failure")
        add_command "Verify kube-root-ca.crt configmap exists" \
                   "kubectl -n monitoring get configmap kube-root-ca.crt" \
                   "kubectl get configmap kube-root-ca.crt -n kube-system"
        add_command "Check if automatic CA injection is working" \
                   "kubectl get namespace monitoring -o yaml" \
                   "kubectl -n monitoring get serviceaccount default -o yaml"
    fi
}

# Function to analyze helm status
analyze_helm() {
    local input="$1"
    
    echo "Analyzing Helm releases..."
    
    if echo "$input" | grep -q "FAILED"; then
        ISSUES+=("Helm release in FAILED state")
        add_command "Check helm release status" \
                   "helm -n monitoring status <release-name>" \
                   "helm -n monitoring history <release-name>"
        add_command "Consider rolling back failed release" \
                   "helm -n monitoring rollback <release-name> <revision>" \
                   "helm -n monitoring status <release-name>" \
                   "true"
    fi
    
    if echo "$input" | grep -q "pending-upgrade"; then
        ISSUES+=("Helm release stuck in pending-upgrade")
        add_command "Check for stuck helm release" \
                   "helm -n monitoring ls --all" \
                   "kubectl -n monitoring get secrets -l owner=helm"
        add_command "Force cleanup of stuck release" \
                   "helm -n monitoring rollback <release-name> 0 --force" \
                   "helm -n monitoring ls" \
                   "true"
    fi
}

# Function to analyze operator logs
analyze_operator_logs() {
    local input="$1"
    
    echo "Analyzing operator logs..."
    
    if echo "$input" | grep -qi "error\|failed\|panic"; then
        ISSUES+=("Operator errors detected in logs")
        add_command "Check operator pod status" \
                   "kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus-operator" \
                   "kubectl -n monitoring describe pods -l app.kubernetes.io/name=prometheus-operator"
        
        if echo "$input" | grep -q "RBAC"; then
            add_command "Check operator RBAC permissions" \
                       "kubectl -n monitoring get clusterrole,clusterrolebinding | grep prometheus-operator" \
                       "kubectl auth can-i create prometheus --as=system:serviceaccount:monitoring:kube-prometheus-stack-operator"
        fi
        
        if echo "$input" | grep -q "CRD"; then
            add_command "Check required CRDs are installed" \
                       "kubectl get crd | grep monitoring.coreos.com" \
                       "kubectl api-resources | grep monitoring"
        fi
    fi
}

# Function to provide prioritized recommendations
generate_recommendations() {
    echo ""
    
    # Provide one-line summary as required
    if [ ${#ISSUES[@]} -eq 0 ]; then
        echo "1) No critical issues detected - monitoring stack appears healthy."
        echo ""
        echo "If problems persist, run these diagnostics:"
        echo "- kubectl top nodes && kubectl top pods -n monitoring"
        echo "- kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default"
        echo "- kubectl get networkpolicy -A"
        return
    fi
    
    # One-line summary of primary cause
    local primary_cause="Multiple issues: Init container failures, missing secrets/configmaps, and node scheduling constraints"
    if echo "${ISSUES[*]}" | grep -q "Volume mount failures"; then
        primary_cause="Missing secrets/configmaps causing volume mount failures and init container crashes"
    elif echo "${ISSUES[*]}" | grep -q "Control plane taints"; then
        primary_cause="Node scheduling issues due to control plane taints and pod affinity constraints"
    fi
    
    echo "1) $primary_cause"
    echo ""
    
    echo "2) Additional diagnostics needed:"
    echo ""
    echo '```bash'
    echo "# Check operator reconciliation status"
    echo "kubectl -n monitoring logs -l app.kubernetes.io/name=prometheus-operator --tail=50"
    echo ""
    echo "# Verify CRD resources are being created"
    echo "kubectl -n monitoring get prometheus,alertmanager,servicemonitor"
    echo ""
    echo "# Check for resource creation errors"
    echo "kubectl -n monitoring get events --sort-by=.metadata.creationTimestamp --no-headers | tail -30"
    echo '```'
    echo ""
    
    echo "3) Safe remediation commands:"
    echo ""
    
    local counter=1
    for cmd_info in "${COMMANDS[@]}"; do
        IFS='|' read -r intent command verification <<< "$cmd_info"
        echo "$counter. Intent: $intent"
        echo '```bash'
        echo "$command"
        echo "# intent: $intent; safe, read-only"
        echo '```'
        echo ""
        echo "Verification:"
        echo '```bash'
        echo "$verification"
        echo '```'
        echo ""
        ((counter++))
    done
    
    if [ ${#DESTRUCTIVE_COMMANDS[@]} -gt 0 ]; then
        echo "4) Destructive actions (requires explicit CONFIRM or AUTO_APPROVE=true):"
        echo ""
        
        for cmd_info in "${DESTRUCTIVE_COMMANDS[@]}"; do
            IFS='|' read -r intent command verification <<< "$cmd_info"
            echo "Intent: $intent"
            echo "Safety check: This command modifies cluster state"
            echo ""
            echo '```bash'
            echo "# SAFETY: Verify impact before running - requires CONFIRM"
            echo "$command"
            echo '```'
            echo ""
            echo "Verification after execution:"
            echo '```bash'
            echo "$verification"
            echo '```'
            echo ""
        done
    fi
}

# Main function to prompt for input and analyze
main() {
    echo "This tool analyzes Kubernetes monitoring diagnostics and provides CLI remediation commands."
    echo ""
    echo "Please provide your diagnostic output by pasting it below."
    echo "Supported inputs:"
    echo "- kubectl get nodes -o wide"
    echo "- kubectl -n monitoring get pods -o wide"  
    echo "- kubectl -n monitoring get events --sort-by=.metadata.creationTimestamp"
    echo "- kubectl -n monitoring get secret,configmap --show-labels"
    echo "- helm -n monitoring ls --all && helm -n monitoring status <release>"
    echo "- kubectl -n monitoring logs <operator-pod> --tail=300"
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
        echo "No input provided. Exiting."
        exit 1
    fi
    
    echo "=== ANALYSIS IN PROGRESS ==="
    echo ""
    
    # Run analysis functions
    analyze_nodes "$input"
    analyze_pods "$input"
    analyze_events "$input"
    analyze_secrets_configmaps "$input"
    analyze_helm "$input"
    analyze_operator_logs "$input"
    
    # Generate final recommendations
    generate_recommendations
    
    echo "=== Analysis Complete ==="
    echo ""
    echo "Summary: Analyzed diagnostics and identified ${#ISSUES[@]} potential issues."
    echo "Follow the safe remediation commands above in order."
    echo "Always verify each step before proceeding to the next."
}

# Run main function
main "$@"