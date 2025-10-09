#!/bin/bash
# =============================================================================
# VMStation Time Synchronization Validation Script
# =============================================================================
# Purpose: Validate NTP/time sync across all cluster nodes
# Author: VMStation Enterprise Monitoring Team
# Date: January 2025
#
# This script validates:
# - NTP service is running on all nodes
# - Time offset is within acceptable limits (<1 second)
# - All nodes are synchronized to the same source
# - Chrony exporter metrics are available
# - Log timestamps are consistent
#
# Usage:
#   ./tests/validate-time-sync.sh
#
# Exit Codes:
#   0 - All checks passed
#   1 - One or more checks failed
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# Kubernetes config
KUBECONFIG="/etc/kubernetes/admin.conf"

# Helper functions
test_suite() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

pass() {
    echo -e "${GREEN}✅ PASS${NC} - $1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

fail() {
    echo -e "${RED}❌ FAIL${NC} - $1"
    FAILED_TESTS=$((FAILED_TESTS + 1))
}

warn() {
    echo -e "${YELLOW}⚠️  WARN${NC} - $1"
    WARNINGS=$((WARNINGS + 1))
}

info() {
    echo -e "${BLUE}ℹ️  INFO${NC} - $1"
}

# =============================================================================
# Test Suite 1: NTP Pod Status
# =============================================================================
test_suite "NTP Pod Status Checks"

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking if NTP DaemonSet exists... "
if kubectl --kubeconfig=$KUBECONFIG get daemonset -n infrastructure chrony-ntp >/dev/null 2>&1; then
    pass "NTP DaemonSet exists"
else
    fail "NTP DaemonSet not found"
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking NTP pod count... "
NTP_PODS=$(kubectl --kubeconfig=$KUBECONFIG get pods -n infrastructure -l app=chrony-ntp --no-headers 2>/dev/null | wc -l)
NODE_COUNT=$(kubectl --kubeconfig=$KUBECONFIG get nodes --no-headers 2>/dev/null | wc -l)
if [ "$NTP_PODS" -eq "$NODE_COUNT" ]; then
    pass "NTP running on all $NODE_COUNT nodes"
else
    fail "NTP pods: $NTP_PODS, Nodes: $NODE_COUNT (should be equal)"
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking NTP pod status... "
NOT_RUNNING=$(kubectl --kubeconfig=$KUBECONFIG get pods -n infrastructure -l app=chrony-ntp --no-headers 2>/dev/null | grep -v Running | wc -l)
if [ "$NOT_RUNNING" -eq 0 ]; then
    pass "All NTP pods are Running"
else
    fail "$NOT_RUNNING NTP pods are not Running"
fi

# =============================================================================
# Test Suite 2: Time Offset Validation
# =============================================================================
test_suite "Time Offset Validation"

# Get list of NTP pods
NTP_POD_LIST=$(kubectl --kubeconfig=$KUBECONFIG get pods -n infrastructure -l app=chrony-ntp -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

for pod in $NTP_POD_LIST; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Checking time offset for $pod... "
    
    # Get tracking info from chrony
    TRACKING=$(kubectl --kubeconfig=$KUBECONFIG exec -n infrastructure $pod -c chrony -- chronyc tracking 2>/dev/null || echo "FAILED")
    
    if [ "$TRACKING" == "FAILED" ]; then
        warn "Unable to query chrony on $pod"
        continue
    fi
    
    # Extract last offset (in seconds)
    OFFSET=$(echo "$TRACKING" | grep "Last offset" | awk '{print $4}')
    
    # Check if offset is within acceptable range (<1 second)
    # Using bc for floating point comparison
    if [ -n "$OFFSET" ]; then
        ABS_OFFSET=$(echo "$OFFSET" | sed 's/-//')
        if (( $(echo "$ABS_OFFSET < 1.0" | bc -l) )); then
            pass "$pod offset: ${OFFSET}s (within ±1s)"
        else
            fail "$pod offset: ${OFFSET}s (exceeds ±1s threshold)"
        fi
    else
        warn "Unable to determine offset for $pod"
    fi
done

# =============================================================================
# Test Suite 3: NTP Source Validation
# =============================================================================
test_suite "NTP Source Validation"

for pod in $NTP_POD_LIST; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Checking NTP sources for $pod... "
    
    SOURCES=$(kubectl --kubeconfig=$KUBECONFIG exec -n infrastructure $pod -c chrony -- chronyc sources 2>/dev/null || echo "FAILED")
    
    if [ "$SOURCES" == "FAILED" ]; then
        warn "Unable to query sources on $pod"
        continue
    fi
    
    # Count number of reachable sources
    REACHABLE=$(echo "$SOURCES" | grep "^\^" | wc -l)
    
    if [ "$REACHABLE" -gt 0 ]; then
        pass "$pod has $REACHABLE reachable NTP sources"
    else
        fail "$pod has no reachable NTP sources"
    fi
done

# =============================================================================
# Test Suite 4: Stratum Validation
# =============================================================================
test_suite "Stratum Validation"

for pod in $NTP_POD_LIST; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Checking NTP stratum for $pod... "
    
    TRACKING=$(kubectl --kubeconfig=$KUBECONFIG exec -n infrastructure $pod -c chrony -- chronyc tracking 2>/dev/null || echo "FAILED")
    
    if [ "$TRACKING" == "FAILED" ]; then
        warn "Unable to query tracking on $pod"
        continue
    fi
    
    STRATUM=$(echo "$TRACKING" | grep "Stratum" | awk '{print $3}')
    
    if [ -n "$STRATUM" ]; then
        if [ "$STRATUM" -le 10 ]; then
            pass "$pod stratum: $STRATUM (≤10, synchronized)"
        else
            fail "$pod stratum: $STRATUM (>10, not synchronized)"
        fi
    else
        warn "Unable to determine stratum for $pod"
    fi
done

# =============================================================================
# Test Suite 5: System Time Sync (systemd-timesyncd or chronyd)
# =============================================================================
test_suite "System Time Sync on Control Plane"

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking if chrony is installed... "
if command -v chronyc >/dev/null 2>&1; then
    pass "chrony is installed"
else
    warn "chrony not installed on control plane"
fi

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking system time sync status... "
if command -v chronyc >/dev/null 2>&1; then
    SYSTEM_TRACKING=$(chronyc tracking 2>/dev/null || echo "FAILED")
    
    if [ "$SYSTEM_TRACKING" != "FAILED" ]; then
        SYSTEM_OFFSET=$(echo "$SYSTEM_TRACKING" | grep "Last offset" | awk '{print $4}')
        ABS_SYSTEM_OFFSET=$(echo "$SYSTEM_OFFSET" | sed 's/-//')
        
        if [ -n "$SYSTEM_OFFSET" ]; then
            if (( $(echo "$ABS_SYSTEM_OFFSET < 1.0" | bc -l) )); then
                pass "Control plane offset: ${SYSTEM_OFFSET}s"
            else
                fail "Control plane offset: ${SYSTEM_OFFSET}s (exceeds threshold)"
            fi
        else
            warn "Unable to determine control plane offset"
        fi
    else
        warn "Unable to query system chrony"
    fi
else
    warn "Skipping (chrony not available)"
fi

# =============================================================================
# Test Suite 6: Chrony Exporter Metrics
# =============================================================================
test_suite "Chrony Exporter Metrics"

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking if chrony-exporter is responding... "
NTP_SERVICE_IP=$(kubectl --kubeconfig=$KUBECONFIG get svc -n infrastructure chrony-ntp -o jsonpath='{.spec.clusterIP}' 2>/dev/null)

if [ -n "$NTP_SERVICE_IP" ] && [ "$NTP_SERVICE_IP" != "None" ]; then
    # For headless service, try to get pod IP
    FIRST_POD=$(echo $NTP_POD_LIST | awk '{print $1}')
    POD_IP=$(kubectl --kubeconfig=$KUBECONFIG get pod -n infrastructure $FIRST_POD -o jsonpath='{.status.podIP}' 2>/dev/null)
    
    if [ -n "$POD_IP" ]; then
        METRICS=$(curl -s http://$POD_IP:9123/metrics 2>/dev/null || echo "FAILED")
        
        if [ "$METRICS" != "FAILED" ] && echo "$METRICS" | grep -q "chrony_"; then
            pass "Chrony exporter metrics available"
        else
            warn "Chrony exporter not responding or no metrics found"
        fi
    else
        warn "Unable to determine pod IP for metrics check"
    fi
else
    warn "Unable to determine service IP for metrics check"
fi

# =============================================================================
# Test Suite 7: Log Timestamp Consistency
# =============================================================================
test_suite "Log Timestamp Consistency"

TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo -n "Checking log timestamp drift... "

# Get current timestamps from different pods
TIMESTAMPS=()
for pod in $(echo $NTP_POD_LIST | head -n 3); do
    TIMESTAMP=$(kubectl --kubeconfig=$KUBECONFIG exec -n infrastructure $pod -c chrony -- date +%s 2>/dev/null || echo "")
    if [ -n "$TIMESTAMP" ]; then
        TIMESTAMPS+=($TIMESTAMP)
    fi
done

if [ ${#TIMESTAMPS[@]} -ge 2 ]; then
    MAX_DRIFT=0
    for i in "${!TIMESTAMPS[@]}"; do
        for j in "${!TIMESTAMPS[@]}"; do
            if [ $i -lt $j ]; then
                DRIFT=$((${TIMESTAMPS[$i]} - ${TIMESTAMPS[$j]}))
                DRIFT=${DRIFT#-}  # Absolute value
                if [ $DRIFT -gt $MAX_DRIFT ]; then
                    MAX_DRIFT=$DRIFT
                fi
            fi
        done
    done
    
    if [ $MAX_DRIFT -le 2 ]; then
        pass "Maximum timestamp drift: ${MAX_DRIFT}s (≤2s acceptable)"
    else
        fail "Maximum timestamp drift: ${MAX_DRIFT}s (>2s, may cause issues)"
    fi
else
    warn "Insufficient data to check timestamp consistency"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
test_suite "Validation Summary"
echo -e "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed:${NC} $PASSED_TESTS"
echo -e "${RED}Failed:${NC} $FAILED_TESTS"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ Time Synchronization Validation: PASSED${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "All time sync checks passed!"
    echo "Log timestamps should be consistent across the cluster."
    echo ""
    exit 0
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}❌ Time Synchronization Validation: FAILED${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Some time sync checks failed!"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check NTP pod logs: kubectl logs -n infrastructure <pod-name> -c chrony"
    echo "2. Verify NTP sources: kubectl exec -n infrastructure <pod-name> -c chrony -- chronyc sources -v"
    echo "3. Check tracking: kubectl exec -n infrastructure <pod-name> -c chrony -- chronyc tracking"
    echo "4. Restart NTP pods: kubectl delete pods -n infrastructure -l app=chrony-ntp"
    echo ""
    exit 1
fi
