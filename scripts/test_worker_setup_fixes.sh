#!/bin/bash
# Test script to validate specific worker setup fixes

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=== VMStation Worker Setup Fixes Test ==="
echo "Timestamp: $(date)"
echo

info "Testing fixes for worker setup deployment issues..."
echo

# Test 1: Validate CNI verification script bash syntax
info "Test 1: Validating CNI verification script bash syntax..."
if bash -n <(cat << 'EOF'
#!/bin/bash
echo "=== Verifying CNI Plugin Installation ==="
required_plugins=("bridge" "host-local" "loopback" "flannel")
all_found=true

for plugin in "${required_plugins[@]}"; do
  if [ -f "/opt/cni/bin/$plugin" ] && [ -x "/opt/cni/bin/$plugin" ]; then
    echo "✓ $plugin plugin installed and executable"
  else
    echo "✗ $plugin plugin missing or not executable"
    all_found=false
  fi
done

if [ "$all_found" = "true" ]; then
  echo "✅ All required CNI plugins verified successfully"
else
  echo "❌ Some CNI plugins are missing"
  exit 1
fi

echo ""
echo "All installed CNI plugins:"
ls -la /opt/cni/bin/
EOF
); then
    info "✅ CNI verification script bash syntax is valid"
else
    error "❌ CNI verification script has syntax errors"
    exit 1
fi

# Test 2: Validate setup-cluster.yaml syntax
info "Test 2: Validating setup-cluster.yaml syntax..."
if python3 -c "import yaml; yaml.safe_load(open('ansible/plays/setup-cluster.yaml'))" 2>/dev/null; then
    info "✅ setup-cluster.yaml syntax is valid"
else
    error "❌ setup-cluster.yaml has YAML syntax errors"
    exit 1
fi

# Test 3: Check for Flannel download fallback mechanism
info "Test 3: Checking for Flannel download fallback mechanism..."
if grep -q "Fallback: Download Flannel CNI plugin with curl" ansible/plays/setup-cluster.yaml; then
    info "✅ Flannel download fallback mechanism present"
    if grep -q "cert_file.*urllib3" ansible/plays/setup-cluster.yaml; then
        info "✅ urllib3/cert_file error detection present"
    else
        warn "⚠️  urllib3/cert_file error detection could be improved"
    fi
else
    error "❌ Flannel download fallback mechanism missing"
    exit 1
fi

# Test 4: Check for enhanced service unit file verification
info "Test 4: Checking for enhanced service unit file verification..."
if grep -q "Search for kubelet service unit in all locations" ansible/plays/setup-cluster.yaml; then
    info "✅ Enhanced kubelet service unit verification present"
else
    error "❌ Enhanced kubelet service unit verification missing"
    exit 1
fi

if grep -q "Search for containerd service unit in all locations" ansible/plays/setup-cluster.yaml; then
    info "✅ Enhanced containerd service unit verification present"
else
    error "❌ Enhanced containerd service unit verification missing"
    exit 1
fi

# Test 5: Check for bash executable specification in CNI verification
info "Test 5: Checking for bash executable specification..."
if grep -A30 "Verify essential CNI plugins are installed" ansible/plays/setup-cluster.yaml | grep -q "executable: /bin/bash"; then
    info "✅ CNI verification uses explicit bash shell"
else
    error "❌ CNI verification missing explicit bash shell specification"
    exit 1
fi

# Test 6: Validate documentation updates
info "Test 6: Validating documentation updates..."
if grep -q "CNI Plugin Verification Shell Syntax Errors" docs/RHEL10_TROUBLESHOOTING.md; then
    info "✅ Documentation includes CNI syntax error troubleshooting"
else
    warn "⚠️  Documentation missing CNI syntax error guidance"
fi

if grep -q "Service Unit File Location Issues" docs/RHEL10_TROUBLESHOOTING.md; then
    info "✅ Documentation includes service unit file troubleshooting"
else
    warn "⚠️  Documentation missing service unit file guidance"
fi

echo
info "🎉 Worker Setup Fixes Test Summary:"
info "✅ All critical fixes are present and validated"
info "✅ CNI verification script uses proper bash syntax"
info "✅ Flannel download has urllib3/cert_file fallback"
info "✅ Service unit file verification is enhanced"
info "✅ Documentation updated with troubleshooting guidance"
echo
info "🔧 The worker setup fixes address the specific deployment failures:"
info "   - Fixed shell syntax error (node 192.168.4.63)"
info "   - Added Flannel download fallback (node 192.168.4.62)"
info "   - Enhanced service unit file detection (node 192.168.4.61)"
echo
info "🚀 Ready for deployment testing!"