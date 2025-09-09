#!/bin/bash

echo "=== Testing Systemd Drop-in Retry Fix ==="
echo "Timestamp: $(date)"
echo

# Test file path
PLAYBOOK_PATH="/home/runner/work/VMStation/VMStation/ansible/plays/kubernetes/setup_cluster.yaml"

# Check if the systemd drop-in update task exists in the retry section
echo "=== Test 1: Systemd Drop-in Update Task in Retry Section ==="
if grep -A 20 "Update systemd drop-in to clean format for retry attempt" "$PLAYBOOK_PATH" | grep -q "10-kubeadm.conf"; then
    echo "[SUCCESS] ✓ Systemd drop-in update task found in retry section"
else
    echo "[FAIL] ✗ Systemd drop-in update task not found in retry section"
    exit 1
fi

# Check if the task uses the clean format without deprecated flags
echo
echo "=== Test 2: Clean Systemd Drop-in Format ==="
DROPIN_SECTION=$(grep -A 25 "Update systemd drop-in to clean format for retry attempt" "$PLAYBOOK_PATH")

if echo "$DROPIN_SECTION" | grep -q "KUBELET_KUBECONFIG_ARGS.*KUBELET_CONFIG_ARGS.*KUBELET_KUBEADM_ARGS.*KUBELET_EXTRA_ARGS"; then
    echo "[SUCCESS] ✓ Clean ExecStart format uses KUBELET_KUBEADM_ARGS (not deprecated individual args)"
else
    echo "[FAIL] ✗ ExecStart format not using clean KUBELET_KUBEADM_ARGS format"
    exit 1
fi

if echo "$DROPIN_SECTION" | grep -q "KUBELET_NETWORK_ARGS\|KUBELET_DNS_ARGS\|KUBELET_AUTHZ_ARGS"; then
    echo "[FAIL] ✗ Systemd drop-in still contains deprecated individual environment variables"
    exit 1
else
    echo "[SUCCESS] ✓ No deprecated individual environment variables (KUBELET_NETWORK_ARGS, etc.)"
fi

# Check if systemd daemon reload is included after drop-in update
echo
echo "=== Test 3: Systemd Daemon Reload After Drop-in Update ==="
if grep -A 30 "Update systemd drop-in to clean format for retry attempt" "$PLAYBOOK_PATH" | grep -q "Reload systemd daemon after updating drop-in"; then
    echo "[SUCCESS] ✓ Systemd daemon reload after drop-in update found"
else
    echo "[FAIL] ✗ Systemd daemon reload after drop-in update not found"
    exit 1
fi

# Check task positioning - should be after sysconfig creation, before join attempt
echo
echo "=== Test 4: Task Positioning in Retry Flow ==="
RETRY_SECTION=$(grep -A 50 "Recreate clean sysconfig/kubelet for retry attempt" "$PLAYBOOK_PATH")

if echo "$RETRY_SECTION" | grep -q "Update systemd drop-in to clean format for retry attempt"; then
    echo "[SUCCESS] ✓ Systemd drop-in update positioned after sysconfig creation"
else
    echo "[FAIL] ✗ Systemd drop-in update not positioned correctly in retry flow"
    exit 1
fi

if echo "$RETRY_SECTION" | grep -A 50 "daemon_reload: yes" | grep -q "Attempt to join cluster (retry with extended timeout)"; then
    echo "[SUCCESS] ✓ Join attempt positioned after systemd reload"
else
    echo "[FAIL] ✗ Join attempt not positioned after systemd reload"
    exit 1
fi

# Validate ansible syntax
echo
echo "=== Test 5: Ansible Syntax Validation ==="
cd /home/runner/work/VMStation/VMStation
if ansible-playbook --syntax-check "$PLAYBOOK_PATH" >/dev/null 2>&1; then
    echo "[SUCCESS] ✓ Ansible syntax is valid"
else
    echo "[FAIL] ✗ Ansible syntax validation failed"
    exit 1
fi

echo
echo "=== All Tests Passed! ==="
echo
echo "Summary of systemd drop-in retry fixes:"
echo "  ✓ Systemd drop-in update task added to retry section"
echo "  ✓ Clean ExecStart format without deprecated environment variables"
echo "  ✓ Systemd daemon reload after drop-in file update"
echo "  ✓ Proper task ordering in retry flow"
echo "  ✓ Ansible syntax validation passes"
echo
echo "[INFO] This fix should resolve the systemd drop-in issues that cause:"
echo "[INFO]   - 'unknown flag: --network-plugin' errors from old Environment variables"
echo "[INFO]   - Kubelet startup failures with deprecated KUBELET_NETWORK_ARGS format"
echo "[INFO]   - Persistence of old systemd configurations during retry attempts"