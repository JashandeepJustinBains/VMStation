#!/usr/bin/env bash
# Wake-on-LAN Utility for VMStation Nodes
# Wakes sleeping nodes using their MAC addresses from inventory
#
# Usage: ./scripts/wake-node.sh [node_name|all] [--wait] [--retry N]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INVENTORY="$REPO_ROOT/inventory.ini"

FLAG_WAIT=false
RETRY_COUNT=3
RETRY_DELAY=30

log_info() { echo "[INFO] $*" >&2; }
log_warn() { echo "[WARN] $*" >&2; }
log_err() { echo "[ERROR] $*" >&2; exit 1; }

usage() {
    cat <<EOF
Wake-on-LAN Utility for VMStation Nodes

Usage: $(basename "$0") [node_name|all] [options]

Arguments:
    node_name    Name of the node to wake (masternode, storagenodet3500, homelab)
    all          Wake all nodes

Options:
    --wait       Wait and verify node is reachable after WoL
    --retry N    Number of retries to ping node (default: 3)
    --delay N    Delay between retries in seconds (default: 30)
    -h, --help   Show this help message

Examples:
    $(basename "$0") homelab                 # Wake homelab node
    $(basename "$0") all --wait              # Wake all nodes and wait
    $(basename "$0") homelab --wait --retry 5

Node MAC Addresses (from inventory):
    masternode:       00:e0:4c:68:cb:bf
    storagenodet3500: b8:ac:6f:7e:6c:9d
    homelab:          d0:94:66:30:d6:63

EOF
}

# Check if wakeonlan tool is available
check_wol_tool() {
    if command -v wakeonlan &>/dev/null; then
        return 0
    elif command -v etherwake &>/dev/null; then
        return 0
    elif command -v wol &>/dev/null; then
        return 0
    else
        log_err "No Wake-on-LAN tool found. Install: apt-get install wakeonlan OR dnf install wol"
    fi
}

# Send WoL magic packet
send_wol() {
    local mac=$1
    local node=$2
    
    log_info "Sending WoL magic packet to $node ($mac)..."
    
    if command -v wakeonlan &>/dev/null; then
        wakeonlan "$mac"
    elif command -v etherwake &>/dev/null; then
        sudo etherwake "$mac"
    elif command -v wol &>/dev/null; then
        wol "$mac"
    else
        log_err "No WoL tool available"
    fi
    
    log_info "✓ WoL packet sent to $node"
}

# Wait for node to be reachable
wait_for_node() {
    local node=$1
    local ip=$2
    local attempts=$3
    
    log_info "Waiting for $node ($ip) to become reachable..."
    
    for ((i=1; i<=attempts; i++)); do
        log_info "Attempt $i/$attempts: Pinging $ip..."
        
        if ping -c 1 -W 5 "$ip" &>/dev/null; then
            log_info "✓ $node is reachable"
            return 0
        fi
        
        if [[ $i -lt $attempts ]]; then
            log_info "Node not reachable yet. Waiting ${RETRY_DELAY}s before retry..."
            sleep "$RETRY_DELAY"
        fi
    done
    
    log_warn "✗ $node did not become reachable after $attempts attempts"
    return 1
}

# Get MAC and IP from inventory
get_node_info() {
    local node=$1
    
    # Use ansible-inventory to extract info
    local mac=$(ansible-inventory -i "$INVENTORY" --host "$node" 2>/dev/null | grep -oP '"wol_mac":\s*"\K[^"]+' || echo "")
    local ip=$(ansible-inventory -i "$INVENTORY" --host "$node" 2>/dev/null | grep -oP '"ansible_host":\s*"\K[^"]+' || echo "")
    
    echo "$mac $ip"
}

# Wake a single node
wake_node() {
    local node=$1
    
    read -r mac ip <<< "$(get_node_info "$node")"
    
    if [[ -z "$mac" ]]; then
        log_err "Could not find MAC address for node: $node"
    fi
    
    if [[ -z "$ip" ]]; then
        log_warn "Could not find IP address for node: $node"
    fi
    
    log_info "Node: $node"
    log_info "  MAC: $mac"
    log_info "  IP: $ip"
    
    send_wol "$mac" "$node"
    
    if [[ "$FLAG_WAIT" == "true" ]] && [[ -n "$ip" ]]; then
        wait_for_node "$node" "$ip" "$RETRY_COUNT"
    fi
}

# Main
main() {
    local target=${1:-}
    
    if [[ -z "$target" ]]; then
        usage
        exit 1
    fi
    
    # Parse options
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --wait) FLAG_WAIT=true; shift ;;
            --retry) RETRY_COUNT=$2; shift 2 ;;
            --delay) RETRY_DELAY=$2; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) log_err "Unknown option: $1"; usage; exit 1 ;;
        esac
    done
    
    check_wol_tool
    
    if [[ "$target" == "all" ]]; then
        log_info "Waking all nodes..."
        for node in masternode storagenodet3500 homelab; do
            wake_node "$node"
            echo ""
        done
    else
        wake_node "$target"
    fi
    
    log_info "Wake-on-LAN complete"
}

main "$@"
