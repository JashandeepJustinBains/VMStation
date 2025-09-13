#!/bin/bash

# VMStation NodePort External Access Validation
# Tests external access to NodePort services to validate the fix

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo "=== VMStation NodePort External Access Validation ==="
echo "Timestamp: $(date)"
echo "Purpose: Validate external access to NodePort services"
echo

# Check prerequisites
if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl is not available"
    exit 1
fi

if ! timeout 10 kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    exit 1
fi

# Test results tracking
PASSED_TESTS=0
FAILED_TESTS=0
TOTAL_TESTS=0

# Function to run a test and track results
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    info "Test $TOTAL_TESTS: $test_name"
    
    if eval "$test_command" >/dev/null 2>&1; then
        success "✅ PASS: $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        error "❌ FAIL: $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Step 1: Get cluster information
info "Step 1: Getting cluster information"

NODE_IPS=$(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}')
info "Cluster nodes: $NODE_IPS"

NODEPORT_SERVICES=$(kubectl get services --all-namespaces -o wide | grep NodePort || echo "")

if [ -z "$NODEPORT_SERVICES" ]; then
    warn "No NodePort services found in the cluster"
    exit 0
fi

echo "NodePort services found:"
echo "$NODEPORT_SERVICES"
echo

# Step 2: Test firewall rules
info "Step 2: Validating firewall configuration"

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    info "Checking UFW rules for NodePort range..."
    
    if ufw status | grep -q "30000:32767"; then
        success "✅ UFW NodePort range rules exist"
    else
        warn "⚠️ UFW NodePort range rules missing"
    fi
    
    # Check for specific ports
    NODEPORTS=$(echo "$NODEPORT_SERVICES" | awk '{print $6}' | grep -o '[0-9]*:[0-9]*' | cut -d: -f2 | sort -n | uniq)
    for port in $NODEPORTS; do
        if ufw status | grep -q "$port"; then
            success "✅ UFW rule exists for port $port"
        else
            warn "⚠️ UFW rule missing for port $port"
        fi
    done
fi

# Step 3: Test iptables configuration
info "Step 3: Validating iptables configuration"

if command -v iptables >/dev/null 2>&1; then
    # Check if KUBE-NODEPORTS chain exists
    run_test "KUBE-NODEPORTS iptables chain exists" "sudo iptables -t nat -L KUBE-NODEPORTS >/dev/null 2>&1"
    
    # Check if there are rules in the chain
    if sudo iptables -t nat -L KUBE-NODEPORTS >/dev/null 2>&1; then
        NODEPORT_RULES=$(sudo iptables -t nat -L KUBE-NODEPORTS --line-numbers | wc -l)
        if [ "$NODEPORT_RULES" -gt 1 ]; then
            success "✅ KUBE-NODEPORTS chain has $((NODEPORT_RULES - 1)) rules"
        else
            warn "⚠️ KUBE-NODEPORTS chain exists but has no rules"
        fi
    fi
    
    # Check for specific NodePort rules
    NODEPORTS=$(echo "$NODEPORT_SERVICES" | awk '{print $6}' | grep -o '[0-9]*:[0-9]*' | cut -d: -f2 | sort -n | uniq)
    for port in $NODEPORTS; do
        if sudo iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
            success "✅ iptables rule exists for TCP port $port"
        else
            warn "⚠️ iptables rule missing for TCP port $port"
        fi
    done
fi

# Step 4: Test NodePort accessibility from localhost
info "Step 4: Testing NodePort accessibility from control plane"

echo "$NODEPORT_SERVICES" | while IFS= read -r line; do
    if [ -n "$line" ] && echo "$line" | grep -q NodePort; then
        namespace=$(echo "$line" | awk '{print $1}')
        service=$(echo "$line" | awk '{print $2}')
        nodeport=$(echo "$line" | awk '{print $6}' | cut -d: -f2 | cut -d/ -f1)
        
        if [ -n "$nodeport" ] && [ "$nodeport" != "<none>" ]; then
            echo
            info "Testing $namespace/$service on NodePort $nodeport"
            
            for node_ip in $NODE_IPS; do
                printf "  Testing %s:%s ... " "$node_ip" "$nodeport"
                
                if timeout 5 curl -s --connect-timeout 3 "http://$node_ip:$nodeport/" >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ accessible${NC}"
                elif timeout 5 curl -s --connect-timeout 3 "http://$node_ip:$nodeport/health" >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ accessible (health endpoint)${NC}"
                elif timeout 5 nc -z "$node_ip" "$nodeport" 2>/dev/null; then
                    echo -e "${YELLOW}⚠️ port open but no HTTP response${NC}"
                else
                    echo -e "${RED}❌ not accessible${NC}"
                fi
            done
        fi
    fi
done

# Step 5: Test specific Jellyfin access
info "Step 5: Testing Jellyfin specific access"

if kubectl get service -n jellyfin jellyfin-service >/dev/null 2>&1; then
    JELLYFIN_NODEPORT=$(kubectl get service -n jellyfin jellyfin-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    
    if [ -n "$JELLYFIN_NODEPORT" ]; then
        info "Testing Jellyfin on NodePort $JELLYFIN_NODEPORT"
        
        # Check pod status first
        if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
            POD_STATUS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.phase}' 2>/dev/null)
            POD_READY=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
            POD_IP=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.podIP}' 2>/dev/null)
            
            info "Jellyfin pod status: $POD_STATUS, ready: $POD_READY, IP: $POD_IP"
            
            # Test each node for Jellyfin access
            for node_ip in $NODE_IPS; do
                printf "  Testing Jellyfin %s:%s ... " "$node_ip" "$JELLYFIN_NODEPORT"
                
                # Try different endpoints that Jellyfin might respond to
                if timeout 10 curl -s --connect-timeout 5 "http://$node_ip:$JELLYFIN_NODEPORT/" >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ Jellyfin accessible${NC}"
                elif timeout 10 curl -s --connect-timeout 5 "http://$node_ip:$JELLYFIN_NODEPORT/web/index.html" >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ Jellyfin web accessible${NC}"
                elif timeout 5 nc -z "$node_ip" "$JELLYFIN_NODEPORT" 2>/dev/null; then
                    echo -e "${YELLOW}⚠️ port open, checking if Jellyfin is starting...${NC}"
                    # Check if Jellyfin is still starting up
                    JELLYFIN_LOGS=$(kubectl logs -n jellyfin jellyfin --tail=5 2>/dev/null | grep -i "startup\|listening\|kestrel" || echo "")
                    if [ -n "$JELLYFIN_LOGS" ]; then
                        echo "    Recent logs suggest Jellyfin is running/starting"
                    fi
                else
                    echo -e "${RED}❌ not accessible${NC}"
                fi
            done
        else
            warn "⚠️ Jellyfin pod not found"
        fi
    fi
else
    warn "⚠️ Jellyfin service not found"
fi

# Step 6: Generate external access test commands
info "Step 6: External access testing guidance"

echo
echo "To test external access from your development desktop, run these commands:"
echo

JELLYFIN_NODEPORT=$(kubectl get service -n jellyfin jellyfin-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "30096")

for node_ip in $NODE_IPS; do
    echo "# Test from external machine to $node_ip:"
    echo "curl -v --connect-timeout 10 http://$node_ip:$JELLYFIN_NODEPORT/"
    echo "# Or in browser: http://$node_ip:$JELLYFIN_NODEPORT/"
    echo
done

echo "If external access fails, check:"
echo "1. External machine can ping cluster nodes: ping $NODE_IPS"
echo "2. No external firewall blocking ports 30000-32767"
echo "3. Router/switch configuration allows traffic"
echo "4. Run this validation again after fixes"

# Final Summary
echo
info "=== Validation Summary ==="
echo "Tests completed: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $FAILED_TESTS"

if [ "$FAILED_TESTS" -eq 0 ]; then
    success "🎉 All validations passed! NodePort external access should work."
    exit 0
else
    warn "⚠️ Some validations failed. Run fix_nodeport_external_access.sh if needed."
    exit 1
fi