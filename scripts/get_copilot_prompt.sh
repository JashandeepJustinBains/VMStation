#!/bin/bash

# Quick Access to Premium Copilot K8s Monitoring Troubleshooting Prompt
# Usage: ./get_copilot_prompt.sh [--copy|--show|--gather]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPT_FILE="$REPO_ROOT/docs/premium_copilot_k8s_monitoring_prompt.md"
COMPLETE_PROMPT_FILE="$REPO_ROOT/docs/premium_copilot_k8s_monitoring_complete_prompt.md"

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
    echo "  --show     Display the template prompt for manual copy (default)"
    echo "  --complete Display the complete prompt with embedded diagnostics"
    echo "  --copy     Copy template prompt to clipboard (requires xclip/pbcopy)"
    echo "  --copy-complete Copy complete prompt to clipboard"
    echo "  --gather   Gather basic cluster diagnostic info"
    echo "  --help     Show this help message"
    echo ""
    echo "VMStation cluster hostnames:"
    echo "  - masternode — 192.168.4.63"
    echo "  - storagenodet3500 — 192.168.4.61" 
    echo "  - homelab — 192.168.4.62"
    echo ""
    echo "Template vs Complete prompt:"
    echo "  --show/--copy: Template prompt (requires separate diagnostic gathering)"
    echo "  --complete/--copy-complete: Ready-to-use prompt with embedded diagnostics"
}

extract_prompt() {
    # Extract just the prompt text between the markers
    sed -n '/^You are an expert Kubernetes troubleshooting assistant/,/^I will paste current pod output when running this prompt/p' "$PROMPT_FILE"
}

extract_complete_prompt() {
    # Extract the complete prompt text from the complete prompt file
    # For now, this uses the static template. In the future, this could be enhanced
    # to embed live diagnostic data when kubectl is available
    sed -n '/^You are an expert Kubernetes troubleshooting assistant/,/^Priority: produce the diagnostic recipes and command sets first/p' "$COMPLETE_PROMPT_FILE"
}

copy_to_clipboard() {
    local prompt_text
    prompt_text=$(extract_prompt)
    
    if command -v pbcopy >/dev/null 2>&1; then
        echo "$prompt_text" | pbcopy
        echo -e "${GREEN}✓${NC} Template prompt copied to clipboard using pbcopy"
    elif command -v xclip >/dev/null 2>&1; then
        echo "$prompt_text" | xclip -selection clipboard
        echo -e "${GREEN}✓${NC} Template prompt copied to clipboard using xclip"
    else
        echo -e "${YELLOW}⚠${NC} Clipboard tool not found (install xclip or pbcopy)"
        echo -e "${BLUE}💡${NC} Showing template prompt for manual copy instead:"
        echo ""
        show_prompt
    fi
}

copy_complete_to_clipboard() {
    local prompt_text
    prompt_text=$(extract_complete_prompt)
    
    if command -v pbcopy >/dev/null 2>&1; then
        echo "$prompt_text" | pbcopy
        echo -e "${GREEN}✓${NC} Complete prompt copied to clipboard using pbcopy"
    elif command -v xclip >/dev/null 2>&1; then
        echo "$prompt_text" | xclip -selection clipboard
        echo -e "${GREEN}✓${NC} Complete prompt copied to clipboard using xclip"
    else
        echo -e "${YELLOW}⚠${NC} Clipboard tool not found (install xclip or pbcopy)"
        echo -e "${BLUE}💡${NC} Showing complete prompt for manual copy instead:"
        echo ""
        show_complete_prompt
    fi
}

show_prompt() {
    echo -e "${BLUE}=== Premium Copilot K8s Monitoring Template Prompt ===${NC}"
    echo ""
    echo -e "${YELLOW}Copy the text below and paste it to premium GitHub Copilot agent:${NC}"
    echo ""
    echo "────────────────────────────────────────────────────────────────"
    extract_prompt
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Copy the template prompt above"
    echo "2. Paste it to premium GitHub Copilot agent"
    echo "3. Gather cluster diagnostics with: $0 --gather"
    echo "4. Paste the diagnostic output to the agent"
    echo ""
    echo -e "${YELLOW}Alternative: Use --complete for a ready-to-use prompt with embedded diagnostics${NC}"
}

show_complete_prompt() {
    echo -e "${BLUE}=== Premium Copilot K8s Complete Prompt with Embedded Diagnostics ===${NC}"
    echo ""
    echo -e "${YELLOW}Copy the text below and paste it to premium GitHub Copilot agent:${NC}"
    echo -e "${GREEN}(No additional diagnostic gathering needed - diagnostics are embedded)${NC}"
    echo ""
    echo "────────────────────────────────────────────────────────────────"
    extract_complete_prompt
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Copy the complete prompt above"
    echo "2. Paste it directly to premium GitHub Copilot agent"
    echo "3. Follow the resulting action plan step-by-step"
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
        echo -e "${YELLOW}⚠${NC} Template prompt file not found: $PROMPT_FILE"
        echo "Make sure you're running this from the VMStation repository root."
        exit 1
    fi
    
    if [[ ! -f "$COMPLETE_PROMPT_FILE" ]]; then
        echo -e "${YELLOW}⚠${NC} Complete prompt file not found: $COMPLETE_PROMPT_FILE"
        echo "Make sure you're running this from the VMStation repository root."
        exit 1
    fi
    
    case "$action" in
        --show|show)
            show_prompt
            ;;
        --complete|complete)
            show_complete_prompt
            ;;
        --copy|copy)
            copy_to_clipboard
            ;;
        --copy-complete|copy-complete)
            copy_complete_to_clipboard
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