#!/bin/bash

# Kubernetes Connectivity Diagnostic Script
# Helps diagnose kubectl timeout and connectivity issues

set -e

echo "=== VMStation Kubernetes Connectivity Diagnostic ==="
echo "Timestamp: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=== Phase 1: Environment Check ==="
echo "User: $(whoami)"
echo "Working directory: $(pwd)"
echo "HOME: $HOME"
echo "KUBECONFIG: ${KUBECONFIG:-not set}"
echo ""

echo "=== Phase 2: kubectl Installation Check ==="
if command -v kubectl >/dev/null 2>&1; then
    echo -e "${GREEN}✓ kubectl found${NC} at $(which kubectl)"
    kubectl version --client --short 2>/dev/null || echo -e "${YELLOW}⚠ Client version check failed${NC}"
else
    echo -e "${RED}✗ kubectl not found${NC}"
    echo "To install kubectl, run:"
    echo "  # On RHEL/CentOS:"
    echo "  sudo dnf install kubectl"
    echo "  # Or download directly:"
    echo "  curl -LO https://storage.googleapis.com/kubernetes-release/release/\$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
    echo ""
fi

echo "=== Phase 3: kubeconfig Check ==="
KUBECONFIG_FILE="${KUBECONFIG:-$HOME/.kube/config}"
if [ -f "$KUBECONFIG_FILE" ]; then
    echo -e "${GREEN}✓ kubeconfig found${NC} at $KUBECONFIG_FILE"
    echo "Permissions: $(ls -la "$KUBECONFIG_FILE")"
    echo ""
    echo "Configuration summary:"
    kubectl config view --minify 2>/dev/null || echo -e "${YELLOW}⚠ Cannot read kubeconfig${NC}"
else
    echo -e "${RED}✗ kubeconfig not found${NC} at $KUBECONFIG_FILE"
    echo "To set up kubeconfig:"
    echo "  1. Copy from master node: scp root@192.168.4.63:/etc/kubernetes/admin.conf ~/.kube/config"
    echo "  2. Set permissions: chmod 600 ~/.kube/config"
    echo "  3. Test: kubectl cluster-info"
fi
echo ""

echo "=== Phase 4: Network Connectivity Test ==="
TARGET_IP="192.168.4.63"
TARGET_PORT="6443"

echo "Testing network connectivity to $TARGET_IP:$TARGET_PORT..."

# Test basic ping
if ping -c 1 -W 3 "$TARGET_IP" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Ping to $TARGET_IP successful${NC}"
else
    echo -e "${RED}✗ Ping to $TARGET_IP failed${NC}"
    echo "  Check if the target node is running and reachable"
fi

# Test port connectivity
if command -v nc >/dev/null 2>&1; then
    if timeout 5 nc -z "$TARGET_IP" "$TARGET_PORT" 2>/dev/null; then
        echo -e "${GREEN}✓ Port $TARGET_PORT is open on $TARGET_IP${NC}"
    else
        echo -e "${RED}✗ Port $TARGET_PORT is not accessible on $TARGET_IP${NC}"
        echo "  Check if Kubernetes API server is running"
        echo "  Check firewall: firewall-cmd --list-ports"
    fi
else
    echo -e "${YELLOW}⚠ nc (netcat) not available for port testing${NC}"
fi

# Test HTTPS connectivity
if command -v curl >/dev/null 2>&1; then
    echo "Testing HTTPS connectivity..."
    if timeout 10 curl -k -s "https://$TARGET_IP:$TARGET_PORT/healthz" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ HTTPS connection to API server successful${NC}"
    else
        echo -e "${RED}✗ HTTPS connection to API server failed${NC}"
        echo "  API server may not be running or accessible"
    fi
fi
echo ""

echo "=== Phase 5: Kubernetes Cluster Test ==="
if command -v kubectl >/dev/null 2>&1 && [ -f "$KUBECONFIG_FILE" ]; then
    echo "Testing kubectl cluster connectivity (10 second timeout)..."
    
    if timeout 10 kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${GREEN}✓ kubectl cluster-info successful${NC}"
        kubectl cluster-info 2>/dev/null || true
        echo ""
        
        echo "Testing kubectl get nodes (5 second timeout)..."
        if timeout 5 kubectl get nodes 2>/dev/null; then
            echo -e "${GREEN}✓ kubectl get nodes successful${NC}"
        else
            echo -e "${YELLOW}⚠ kubectl get nodes timed out or failed${NC}"
        fi
    else
        echo -e "${RED}✗ kubectl cluster-info failed or timed out${NC}"
        echo "Common causes:"
        echo "  - API server not running: systemctl status kubelet"
        echo "  - Wrong server endpoint in kubeconfig"
        echo "  - Certificate issues"
        echo "  - Network/firewall blocking access"
    fi
else
    echo -e "${YELLOW}⚠ Skipping kubectl tests (kubectl or kubeconfig missing)${NC}"
fi
echo ""

echo "=== Phase 6: Process and Service Check ==="
echo "Checking for Kubernetes processes..."
if pgrep -f "kube-apiserver\|kubelet\|kube-controller\|kube-scheduler" >/dev/null; then
    echo -e "${GREEN}✓ Kubernetes processes found:${NC}"
    ps aux | grep -E "(kube-apiserver|kubelet|kube-controller|kube-scheduler)" | grep -v grep | sed 's/^/  /'
else
    echo -e "${RED}✗ No Kubernetes processes found${NC}"
    echo "Check if Kubernetes services are running:"
    echo "  systemctl status kubelet"
    echo "  systemctl status docker  # or containerd"
fi
echo ""

echo "=== Phase 7: Firewall and Port Check ==="
if command -v firewall-cmd >/dev/null 2>&1; then
    echo "Firewall status:"
    firewall-cmd --state 2>/dev/null || echo "Firewall not running"
    echo "Open ports:"
    firewall-cmd --list-ports 2>/dev/null || echo "Cannot list ports"
    
    # Check if API server port is open
    if firewall-cmd --list-ports 2>/dev/null | grep -q "6443"; then
        echo -e "${GREEN}✓ API server port 6443 is open in firewall${NC}"
    else
        echo -e "${YELLOW}⚠ API server port 6443 not explicitly open in firewall${NC}"
        echo "To open: firewall-cmd --permanent --add-port=6443/tcp && firewall-cmd --reload"
    fi
else
    echo "firewall-cmd not available - cannot check firewall status"
fi
echo ""

echo "=== Phase 8: Recommendations ==="
echo "Based on the above diagnostics:"
echo ""

# Check if main issues are present
if ! command -v kubectl >/dev/null 2>&1; then
    echo -e "${RED}1. Install kubectl${NC}"
fi

if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo -e "${RED}2. Set up kubeconfig file${NC}"
fi

if ! ping -c 1 -W 3 "$TARGET_IP" >/dev/null 2>&1; then
    echo -e "${RED}3. Fix network connectivity to $TARGET_IP${NC}"
fi

if ! pgrep -f "kubelet" >/dev/null; then
    echo -e "${RED}4. Start kubelet service: systemctl start kubelet${NC}"
fi

echo ""
echo "=== Next Steps ==="
echo "If Kubernetes is accessible:"
echo "  - Run: ./update_and_deploy.sh"
echo ""
echo "If Kubernetes is not accessible:"
echo "  - Fix the issues identified above"
echo "  - Or run with non-Kubernetes playbooks only:"
echo "    FORCE_K8S_DEPLOYMENT=false ./update_and_deploy.sh"
echo ""
echo "For more help:"
echo "  - Check logs: journalctl -u kubelet -f"
echo "  - Review cluster setup: kubectl cluster-info dump"
echo ""
echo "🔍 Diagnostic complete!"