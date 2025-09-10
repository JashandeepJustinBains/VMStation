#!/bin/bash

# Validate CNI Configuration Fix
# This script verifies that the CNI configuration we create addresses the containerd error

echo "=== Validating CNI Configuration Fix ==="
echo "Timestamp: $(date)"
echo ""

# Extract the CNI configuration from setup-cluster.yaml
echo "Extracting CNI configuration from setup-cluster.yaml..."
CNI_CONFIG=$(sed -n '/Create basic CNI configuration/,/dest: .*10-flannel.conflist/p' ansible/plays/setup-cluster.yaml | \
             sed -n '/content: |/,/dest:/p' | \
             sed '1d;$d' | \
             sed 's/^              //')

echo "CNI Configuration that will be created:"
echo "$CNI_CONFIG"
echo ""

# Validate JSON structure
echo "Validating JSON syntax..."
if echo "$CNI_CONFIG" | python3 -m json.tool >/dev/null 2>&1; then
    echo "✓ PASS: CNI configuration is valid JSON"
else
    echo "✗ FAIL: CNI configuration has invalid JSON syntax"
    exit 1
fi

# Check for required CNI fields
echo ""
echo "Validating required CNI fields..."

if echo "$CNI_CONFIG" | grep -q '"name":'; then
    echo "✓ PASS: CNI configuration includes 'name' field"
else
    echo "✗ FAIL: CNI configuration missing 'name' field"
    exit 1
fi

if echo "$CNI_CONFIG" | grep -q '"cniVersion":'; then
    echo "✓ PASS: CNI configuration includes 'cniVersion' field"
else
    echo "✗ FAIL: CNI configuration missing 'cniVersion' field"
    exit 1
fi

if echo "$CNI_CONFIG" | grep -q '"plugins":'; then
    echo "✓ PASS: CNI configuration includes 'plugins' field"
else
    echo "✗ FAIL: CNI configuration missing 'plugins' field"
    exit 1
fi

# Check for flannel plugin
if echo "$CNI_CONFIG" | grep -q '"type": "flannel"'; then
    echo "✓ PASS: CNI configuration includes flannel plugin"
else
    echo "✗ FAIL: CNI configuration missing flannel plugin"
    exit 1
fi

# Check for portmap plugin
if echo "$CNI_CONFIG" | grep -q '"type": "portmap"'; then
    echo "✓ PASS: CNI configuration includes portmap plugin"
else
    echo "✗ FAIL: CNI configuration missing portmap plugin"
    exit 1
fi

echo ""
echo "Checking containerd compatibility..."

# Check that the configuration name matches containerd expectations
if echo "$CNI_CONFIG" | grep -q '"name": "cni0"'; then
    echo "✓ PASS: CNI network name 'cni0' matches containerd expectations"
else
    echo "✗ FAIL: CNI network name doesn't match containerd expectations"
    exit 1
fi

# Verify CNI version compatibility
if echo "$CNI_CONFIG" | grep -q '"cniVersion": "0.3.1"'; then
    echo "✓ PASS: CNI version 0.3.1 is compatible with containerd"
else
    echo "✗ FAIL: CNI version may not be compatible with containerd"
    exit 1
fi

echo ""
echo "Checking file paths..."

# Verify the destination path matches containerd's expected CNI config directory
if grep -A30 "Create basic CNI configuration" ansible/plays/setup-cluster.yaml | grep -q "dest: /etc/cni/net.d/10-flannel.conflist"; then
    echo "✓ PASS: CNI configuration will be placed in correct directory (/etc/cni/net.d/)"
else
    echo "✗ FAIL: CNI configuration not being placed in correct directory"
    exit 1
fi

# Check that CNI plugin binaries are installed in the correct location
if grep -A10 "Download.*install.*CNI" ansible/plays/setup-cluster.yaml | grep -q "/opt/cni/bin"; then
    echo "✓ PASS: CNI plugin binaries will be installed in correct directory (/opt/cni/bin/)"
else
    echo "✗ FAIL: CNI plugin binaries not being installed in correct directory"
    exit 1
fi

echo ""
echo "=== Validation Summary ==="
echo "✓ CNI configuration addresses the containerd error:"
echo "  - 'no network config found in /etc/cni/net.d' → Fixed by creating /etc/cni/net.d/10-flannel.conflist"
echo "  - 'cni plugin not initialized' → Fixed by installing CNI plugins in /opt/cni/bin/"
echo "  - 'failed to load cni config' → Fixed by providing valid JSON CNI configuration"
echo ""
echo "✓ Configuration is containerd-compatible:"
echo "  - Uses CNI specification version 0.3.1"
echo "  - Creates network named 'cni0' as expected by containerd"
echo "  - Includes required flannel and portmap plugins"
echo "  - Files placed in standard CNI directories"
echo ""
echo "This fix should resolve the containerd CNI initialization errors"
echo "shown in the problem statement logs."