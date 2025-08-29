#!/bin/bash

# Quick Access to Premium Copilot K8s Monitoring Troubleshooting Prompt
# Usage: ./get_copilot_prompt.sh [--copy|--show|--gather]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPT_FILE="$REPO_ROOT/docs/premium_copilot_k8s_monitoring_prompt.md"

# Color codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

show_usage() {
    echo "Premium Copilot K8s Monitoring Troubleshooting Helper"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  --show     Display the prompt for manual copy (default)"
    echo "  --copy     Copy prompt to clipboard (requires xclip/pbcopy)"
    echo "  --gather   Gather basic cluster diagnostic info"
    echo "  --help     Show this help message"
    echo ""
    echo "VMStation cluster hostnames:"
    echo "  - masternode — 192.168.4.63"
    echo "  - storagenodet3500 — 192.168.4.61" 
    echo "  - localhost.localdomain — 192.168.4.62"
}

extract_prompt() {
    # Extract just the prompt text between the markers
    sed -n '/^You are an expert Kubernetes troubleshooting assistant/,/^I will paste current pod output when running this prompt/p' "$PROMPT_FILE"
}

copy_to_clipboard() {
    local prompt_text
    prompt_text=$(extract_prompt)
    
    if command -v pbcopy >/dev/null 2>&1; then
        echo "$prompt_text" | pbcopy
        echo -e "${GREEN}✓${NC} Prompt copied to clipboard using pbcopy"
    elif command -v xclip >/dev/null 2>&1; then
        echo "$prompt_text" | xclip -selection clipboard
        echo -e "${GREEN}✓${NC} Prompt copied to clipboard using xclip"
    else
        echo -e "${YELLOW}⚠${NC} Clipboard tool not found (install xclip or pbcopy)"
        echo -e "${BLUE}💡${NC} Showing prompt for manual copy instead:"
        echo ""
        show_prompt
    fi
}

show_prompt() {
    echo -e "${BLUE}=== Premium Copilot K8s Monitoring Troubleshooting Prompt ===${NC}"
    echo ""
    echo -e "${YELLOW}Copy the text below and paste it to premium GitHub Copilot agent:${NC}"
    echo ""
    echo "────────────────────────────────────────────────────────────────"
    extract_prompt
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Copy the prompt above"
    echo "2. Paste it to premium GitHub Copilot agent"
    echo "3. Gather cluster diagnostics with: $0 --gather"
    echo "4. Paste the diagnostic output to the agent"
}

gather_diagnostics() {
    echo -e "${BLUE}=== Gathering Basic K8s Monitoring Diagnostics ===${NC}"
    echo ""
    echo "Running basic diagnostic commands for monitoring namespace..."
    echo "Use this output when prompted by the premium Copilot agent."
    echo ""
    
    echo "────────────────────────────────────────────────────────────────"
    echo "# Cluster and node information"
    echo "kubectl get nodes -o wide"
    if command -v kubectl >/dev/null 2>&1; then
        kubectl get nodes -o wide 2>/dev/null || echo "kubectl not available or cluster not accessible"
    else
        echo "kubectl command not found"
    fi
    echo ""
    
    echo "# Monitoring namespace pods"
    echo "kubectl -n monitoring get pods -o wide"
    if command -v kubectl >/dev/null 2>&1; then
        kubectl -n monitoring get pods -o wide 2>/dev/null || echo "monitoring namespace not found or not accessible"
    else
        echo "kubectl command not found"
    fi
    echo ""
    
    echo "# Recent events in monitoring namespace"
    echo "kubectl -n monitoring get events --sort-by='.lastTimestamp' | tail -20"
    if command -v kubectl >/dev/null 2>&1; then
        kubectl -n monitoring get events --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || echo "events not accessible"
    else
        echo "kubectl command not found"
    fi
    echo ""
    
    echo "# PVCs in monitoring namespace"
    echo "kubectl -n monitoring get pvc"
    if command -v kubectl >/dev/null 2>&1; then
        kubectl -n monitoring get pvc 2>/dev/null || echo "PVCs not accessible"
    else
        echo "kubectl command not found"
    fi
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo -e "${GREEN}✓${NC} Basic diagnostics complete. Copy the output above to provide to the premium Copilot agent."
    echo ""
    echo -e "${YELLOW}For deeper diagnostics, the agent may ask you to run additional commands like:${NC}"
    echo "  - kubectl -n monitoring describe pod <failing-pod-name>"
    echo "  - kubectl -n monitoring logs <failing-pod-name> --previous"
    echo "  - kubectl get pv <pv-name> -o yaml"
}

main() {
    local action="${1:-show}"
    
    if [[ ! -f "$PROMPT_FILE" ]]; then
        echo -e "${YELLOW}⚠${NC} Prompt file not found: $PROMPT_FILE"
        echo "Make sure you're running this from the VMStation repository root."
        exit 1
    fi
    
    case "$action" in
        --show|show)
            show_prompt
            ;;
        --copy|copy)
            copy_to_clipboard
            ;;
        --gather|gather)
            gather_diagnostics
            ;;
        --help|help|-h)
            show_usage
            ;;
        *)
            echo -e "${YELLOW}⚠${NC} Unknown option: $action"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

main "$@"