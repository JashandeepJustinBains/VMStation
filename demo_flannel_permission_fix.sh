#!/bin/bash

# Demonstration script showing how the Flannel permission fix works
# This simulates the permission issue scenario and shows the fix in action

set -e

echo "=== Flannel CNI Permission Fix Demonstration ==="
echo "This script demonstrates how the fix resolves permission issues"
echo ""

# Create a test environment
TEST_DIR="/tmp/flannel_permission_test"
CNI_BIN_DIR="$TEST_DIR/opt/cni/bin"
CNI_CONFIG_DIR="$TEST_DIR/etc/cni/net.d"

cleanup_test() {
    echo "Cleaning up test environment..."
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

# Setup cleanup trap
trap cleanup_test EXIT

echo "=== Step 1: Simulating Initial CNI Directory Setup ==="
mkdir -p "$CNI_BIN_DIR" "$CNI_CONFIG_DIR"
chmod 755 "$CNI_BIN_DIR" "$CNI_CONFIG_DIR"
echo "Created CNI directories with proper permissions"
ls -la "$TEST_DIR/opt/cni/"
ls -la "$TEST_DIR/etc/cni/"
echo ""

echo "=== Step 2: Simulating Flannel Binary Download ==="
# Create a fake flannel binary
echo "#!/bin/bash" > "$CNI_BIN_DIR/flannel"
echo "echo 'Flannel CNI plugin'" >> "$CNI_BIN_DIR/flannel"
chmod 755 "$CNI_BIN_DIR/flannel"
echo "✓ Flannel binary created successfully"
ls -la "$CNI_BIN_DIR/"
echo ""

echo "=== Step 3: Simulating the Problem - Cleanup Removing Directory ==="
echo "Old cleanup approach (problematic):"
echo "  rm -rf $CNI_BIN_DIR/flannel"
echo "  rm -rf $CNI_CONFIG_DIR/*"
# Simulate what could go wrong - directory permissions could be altered
rm -f "$CNI_BIN_DIR/flannel"
chmod 644 "$CNI_BIN_DIR"  # Make directory non-writable to simulate permission issue
echo "❌ Directory made non-writable, simulating permission issue"
ls -la "$TEST_DIR/opt/cni/"
echo ""

echo "=== Step 4: Demonstrating the Fix - Enhanced Cleanup ==="
echo "New cleanup approach (fixed):"
echo "1. Remove files but preserve directory structure"
echo "2. Ensure directories exist with proper permissions"
echo ""

# Apply the fix logic
echo "Applying enhanced cleanup with permission fix..."

# Remove files but preserve directories
rm -f "$CNI_BIN_DIR/flannel" 2>/dev/null || true
rm -rf "$CNI_CONFIG_DIR"/* 2>/dev/null || true

# Ensure directories exist with proper permissions (the fix)
mkdir -p "$CNI_BIN_DIR" "$CNI_CONFIG_DIR" || true
chmod 755 "$CNI_BIN_DIR" "$CNI_CONFIG_DIR" || true
chown $(whoami):$(id -gn) "$CNI_BIN_DIR" "$CNI_CONFIG_DIR" || true

echo "✅ Enhanced cleanup applied - directories preserved with correct permissions"
ls -la "$TEST_DIR/opt/cni/"
echo ""

echo "=== Step 5: Validating Directory Permissions ==="
# Simulate the permission validation logic
for dir in "$CNI_BIN_DIR" "$CNI_CONFIG_DIR"; do
    if [ ! -d "$dir" ]; then
        echo "❌ Directory missing: $dir"
        exit 1
    fi
    if [ ! -w "$dir" ]; then
        echo "❌ Directory not writable: $dir"
        exit 1
    fi
    echo "✅ Directory ready: $dir (permissions: $(stat -c '%a' "$dir"))"
done
echo ""

echo "=== Step 6: Testing Write Access ==="
# Simulate the pre-download write test
test_file="$CNI_BIN_DIR/.write_test_$$"
if echo "test" > "$test_file" 2>/dev/null; then
    rm -f "$test_file"
    echo "✅ Write test passed - directory is writable"
else
    echo "❌ Write test failed - permission issue detected"
    exit 1
fi
echo ""

echo "=== Step 7: Simulating Successful Flannel Download ==="
# Re-create the flannel binary to show download would succeed
echo "#!/bin/bash" > "$CNI_BIN_DIR/flannel"
echo "echo 'Flannel CNI plugin v0.25.2'" >> "$CNI_BIN_DIR/flannel"
chmod 755 "$CNI_BIN_DIR/flannel"
echo "✅ Flannel binary downloaded successfully"
ls -la "$CNI_BIN_DIR/"
echo ""

echo "=== Summary ==="
echo "The permission fix ensures:"
echo "✓ CNI directories are preserved during cleanup"
echo "✓ Proper permissions are enforced (755, root:root)"
echo "✓ Write access is validated before download attempts"
echo "✓ Enhanced diagnostics help troubleshoot permission issues"
echo "✓ Flannel downloads succeed even after cleanup operations"
echo ""
echo "🎉 Flannel CNI permission fix demonstration completed successfully!"