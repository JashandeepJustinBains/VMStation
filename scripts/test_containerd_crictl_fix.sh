#!/bin/bash

# Test script to verify containerd/crictl communication fix
# This simulates the problematic scenario and tests the recovery logic

set -e

echo "=== VMStation Containerd/Crictl Communication Test ==="
echo "Timestamp: $(date)"
echo ""

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Test if containerd is running
if ! systemctl is-active containerd >/dev/null 2>&1; then
    error "containerd is not running. Starting it..."
    systemctl start containerd
    sleep 5
fi

info "Containerd service status: $(systemctl is-active containerd)"

# Test if crictl config exists
if [ ! -f /etc/crictl.yaml ]; then
    info "Creating crictl configuration..."
    cat > /etc/crictl.yaml << 'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF
fi

# Test 1: Basic crictl communication
info "Test 1: Basic crictl communication test..."
if timeout 20 crictl info >/dev/null 2>&1; then
    info "✓ Basic crictl communication working"
else
    warn "✗ Basic crictl communication failed"
fi

# Test 2: Socket existence and permissions
info "Test 2: Socket validation..."
if [ -S /run/containerd/containerd.sock ]; then
    info "✓ Containerd socket exists"
    ls -la /run/containerd/containerd.sock
else
    error "✗ Containerd socket missing"
    exit 1
fi

# Test 3: Containerd service detailed status
info "Test 3: Containerd service detailed status..."
systemctl status containerd --no-pager || true

# Test 4: Test namespace creation and image operations
info "Test 4: Containerd namespace and image operations..."
ctr namespace create k8s.io 2>/dev/null || true
if timeout 30 ctr --namespace k8s.io images ls >/dev/null 2>&1; then
    info "✓ Containerd image operations working"
else
    warn "✗ Containerd image operations failed"
fi

# Test 5: Progressive timeout test (simulating the fix)
info "Test 5: Progressive timeout testing..."
for timeout_val in 15 30 45 60; do
    info "  Testing with ${timeout_val}s timeout..."
    if timeout $timeout_val crictl info >/dev/null 2>&1; then
        info "  ✓ Success with ${timeout_val}s timeout"
        break
    else
        warn "  ✗ Failed with ${timeout_val}s timeout"
    fi
done

# Test 6: Stress test - rapid crictl calls
info "Test 6: Stress testing crictl communication..."
success_count=0
for i in {1..5}; do
    if timeout 10 crictl info >/dev/null 2>&1; then
        ((success_count++))
    fi
    sleep 1
done
info "Stress test: $success_count/5 successful crictl calls"

# Test 7: Memory and disk space check
info "Test 7: System resource check..."
echo "Memory usage:"
free -m | head -2
echo "Disk space for containerd:"
df -h /var/lib/containerd 2>/dev/null || echo "Containerd directory not accessible"

info "=== Test completed ==="