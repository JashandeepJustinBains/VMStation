#!/bin/bash

# VMStation API Server Connectivity Fix - Validation Script
# This script validates the implemented fix for worker node join failures

echo "=== VMStation API Server Connectivity Fix - Validation ==="
echo "Timestamp: $(date)"
echo ""
echo "This script validates the fix for the error:"
echo "  'dial tcp 192.168.4.63:6443: connect: connection refused'"
echo ""

# Test 1: Ansible Syntax Validation
echo "✓ Test 1: Ansible Playbook Syntax"
if ansible-playbook -i ansible/inventory.txt --syntax-check ansible/plays/setup-cluster.yaml >/dev/null 2>&1; then
    echo "  ✅ setup-cluster.yaml syntax is valid"
else
    echo "  ❌ setup-cluster.yaml has syntax errors"
    exit 1
fi

if ansible-playbook -i ansible/inventory.txt --syntax-check ansible/simple-deploy.yaml >/dev/null 2>&1; then
    echo "  ✅ simple-deploy.yaml syntax is valid"
else
    echo "  ❌ simple-deploy.yaml has syntax errors"
    exit 1
fi

echo ""

# Test 2: Firewall Configuration
echo "✓ Test 2: Firewall Port Configuration"
required_ports=("6443/tcp" "10250/tcp" "10251/tcp" "10252/tcp" "8472/udp")
for port in "${required_ports[@]}"; do
    if grep -q "$port" ansible/plays/setup-cluster.yaml; then
        echo "  ✅ Port $port configured"
    else
        echo "  ❌ Port $port missing"
        exit 1
    fi
done

echo ""

# Test 3: API Server Readiness
echo "✓ Test 3: API Server Readiness Validation"
if grep -q "Wait for API server to be ready" ansible/plays/setup-cluster.yaml; then
    echo "  ✅ API server port readiness check added"
else
    echo "  ❌ API server port readiness check missing"
    exit 1
fi

if grep -q "/healthz" ansible/plays/setup-cluster.yaml; then
    echo "  ✅ API server health endpoint validation added"
else
    echo "  ❌ API server health endpoint validation missing"
    exit 1
fi

echo ""

# Test 4: CNI Installation Improvements
echo "✓ Test 4: CNI Installation Robustness"
if ! grep -q "when: kubeadm_init is changed" ansible/plays/setup-cluster.yaml; then
    echo "  ✅ CNI installation no longer dependent on kubeadm_init state"
else
    echo "  ❌ CNI installation still has restrictive conditional"
    exit 1
fi

if grep -A 8 "Install Flannel CNI" ansible/plays/setup-cluster.yaml | grep -q "retries:"; then
    echo "  ✅ CNI installation has retry logic"
else
    echo "  ❌ CNI installation lacks retry logic"
    exit 1
fi

echo ""

# Test 5: Worker Join Enhancements
echo "✓ Test 5: Worker Join Process Improvements"
if grep -q "Test connectivity to control plane API server" ansible/plays/setup-cluster.yaml; then
    echo "  ✅ Pre-join connectivity test added"
else
    echo "  ❌ Pre-join connectivity test missing"
    exit 1
fi

if grep -A 8 "Join cluster with retry logic" ansible/plays/setup-cluster.yaml | grep -q "retries:"; then
    echo "  ✅ Join operation has retry mechanism"
else
    echo "  ❌ Join operation lacks retry mechanism"
    exit 1
fi

if grep -q "Display join result" ansible/plays/setup-cluster.yaml; then
    echo "  ✅ Enhanced error reporting added"
else
    echo "  ❌ Enhanced error reporting missing"
    exit 1
fi

echo ""
echo "🎉 All validation tests passed!"
echo ""
echo "=== Summary of Implemented Fix ==="
echo ""
echo "Problem: Worker nodes failing to join cluster with:"
echo "  'error execution phase preflight: couldn't validate the identity of the API Server'"
echo "  'Get \"https://192.168.4.63:6443/...\": dial tcp 192.168.4.63:6443: connect: connection refused'"
echo ""
echo "Root Cause Analysis:"
echo "  • API server not fully ready when worker joins attempted"
echo "  • Firewall blocking Kubernetes ports (especially 6443)"
echo "  • CNI installation conditional on kubeadm_init change state"
echo "  • No connectivity pre-validation or retry logic"
echo ""
echo "Implemented Solution:"
echo "  1. ✅ Firewall Configuration - Opens all required Kubernetes ports"
echo "  2. ✅ API Server Readiness - Waits for port 6443 and /healthz endpoint"
echo "  3. ✅ CNI Installation Fix - Removes restrictive conditional, adds retries"
echo "  4. ✅ Join Process Enhancement - Adds connectivity tests and retry logic"
echo "  5. ✅ Error Diagnostics - Better troubleshooting information"
echo ""
echo "Expected Outcome:"
echo "  • API server accessible on port 6443 before worker joins"
echo "  • Firewall properly configured for Kubernetes traffic"
echo "  • Robust join process with automatic retry on transient failures"
echo "  • Better error messages for troubleshooting remaining issues"
echo ""
echo "To deploy the fix:"
echo "  ./deploy.sh cluster  # Deploy only cluster setup with fixes"
echo "  ./deploy.sh full     # Deploy complete VMStation stack"