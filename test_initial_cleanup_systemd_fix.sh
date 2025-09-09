#!/bin/bash

echo "=== Testing Initial Cleanup Systemd Fix ==="
echo "Timestamp: $(date)"
echo

# Test file path
PLAYBOOK_PATH="/home/runner/work/VMStation/VMStation/ansible/plays/kubernetes/setup_cluster.yaml"

# Check if the initial cleanup removes systemd drop-in files
echo "=== Test 1: Initial Cleanup Removes Systemd Drop-in Files ==="
if grep -A 20 "Clear comprehensive kubelet state" "$PLAYBOOK_PATH" | grep -q "rm -f /etc/systemd/system/kubelet.service.d/10-kubeadm.conf"; then
    echo "[SUCCESS] ✓ Initial cleanup removes existing systemd drop-in files"
else
    echo "[FAIL] ✗ Initial cleanup does not remove existing systemd drop-in files"
    exit 1
fi

# Check if the initial cleanup removes sysconfig files
echo
echo "=== Test 2: Initial Cleanup Removes Sysconfig Files ==="
if grep -A 20 "Clear comprehensive kubelet state" "$PLAYBOOK_PATH" | grep -q "rm -f /etc/sysconfig/kubelet"; then
    echo "[SUCCESS] ✓ Initial cleanup removes existing sysconfig/kubelet files"
else
    echo "[FAIL] ✗ Initial cleanup does not remove existing sysconfig/kubelet files"
    exit 1
fi

# Check if systemd daemon reload is added after drop-in configuration
echo
echo "=== Test 3: Systemd Daemon Reload After Drop-in Configuration ==="
if grep -A 10 "when: not recovery_kubelet_conf_check.stat.exists" "$PLAYBOOK_PATH" | grep -q "daemon_reload"; then
    echo "[SUCCESS] ✓ Systemd daemon reload after drop-in configuration update found"
else
    echo "[FAIL] ✗ Systemd daemon reload after drop-in configuration update not found"
    exit 1
fi

# Validate that the fix doesn't break existing retry logic
echo
echo "=== Test 4: Existing Retry Logic Integrity ==="
if grep -A 25 "Update systemd drop-in to clean format for retry attempt" "$PLAYBOOK_PATH" | grep -q "daemon_reload"; then
    echo "[SUCCESS] ✓ Existing retry systemd daemon reload still present"
else
    echo "[FAIL] ✗ Existing retry systemd daemon reload missing"
    exit 1
fi

# Check for proper task ordering
echo
echo "=== Test 5: Proper Task Ordering ==="
# Clear state should come before regenerate kubelet service
CLEAR_LINE=$(grep -n "Clear comprehensive kubelet state" "$PLAYBOOK_PATH" | cut -d: -f1)
REGENERATE_LINE=$(grep -n "Regenerate kubelet service configuration" "$PLAYBOOK_PATH" | cut -d: -f1)

if [ "$CLEAR_LINE" -lt "$REGENERATE_LINE" ]; then
    echo "[SUCCESS] ✓ Clear state comes before regenerate kubelet service configuration"
else
    echo "[FAIL] ✗ Task ordering is incorrect"
    exit 1
fi

# Validate Ansible syntax
echo
echo "=== Test 6: Ansible Syntax Validation ==="
if ansible-playbook --syntax-check "$PLAYBOOK_PATH" >/dev/null 2>&1; then
    echo "[SUCCESS] ✓ Ansible syntax is valid"
else
    echo "[FAIL] ✗ Ansible syntax validation failed"
    exit 1
fi

echo
echo "=== All Tests Passed! ==="
echo
echo "Summary of initial cleanup systemd fixes:"
echo "  ✓ Initial cleanup removes existing systemd drop-in files with deprecated flags"
echo "  ✓ Initial cleanup removes existing sysconfig files with deprecated flags" 
echo "  ✓ Systemd daemon reload after drop-in configuration update"
echo "  ✓ Existing retry logic remains intact"
echo "  ✓ Proper task ordering maintained"
echo "  ✓ Ansible syntax validation passes"
echo
echo "[INFO] This fix should resolve the initial setup issues that cause:"
echo "[INFO]   - 'unknown flag: --network-plugin' errors from existing systemd configurations"
echo "[INFO]   - Kubelet startup failures due to conflicting systemd drop-in files"
echo "[INFO]   - Need to rely only on retry mechanisms for cleaning deprecated configurations"