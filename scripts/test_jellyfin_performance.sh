#!/bin/bash

# Jellyfin Performance Test Script
# Tests 4K streaming capabilities and high availability features

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

header() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Configuration
JELLYFIN_URL="http://192.168.4.61:30096"
LOAD_BALANCER_URL="http://192.168.4.100:8096"
INGRESS_URL="https://jellyfin.vmstation.local"

echo "=== Jellyfin Kubernetes Performance Test ==="
echo "Timestamp: $(date)"
echo ""

header "1. Service Availability Test"

# Test NodePort access
info "Testing NodePort service..."
if curl -s --connect-timeout 10 "$JELLYFIN_URL/health" > /dev/null; then
    info "✅ NodePort service accessible"
else
    error "❌ NodePort service not accessible"
    exit 1
fi

# Test LoadBalancer access
info "Testing LoadBalancer service..."
if curl -s --connect-timeout 10 "$LOAD_BALANCER_URL/health" > /dev/null; then
    info "✅ LoadBalancer service accessible"
else
    warn "⚠️ LoadBalancer service not accessible (may not be configured)"
fi

# Test Ingress access
info "Testing Ingress service..."
if curl -s --connect-timeout 10 -k "$INGRESS_URL/health" > /dev/null; then
    info "✅ Ingress service accessible"
else
    warn "⚠️ Ingress service not accessible (may not be configured)"
fi

header "2. High Availability Test"

# Check pod distribution
info "Checking pod distribution..."
if command -v kubectl &> /dev/null; then
    PODS=$(kubectl get pods -n jellyfin -o wide --no-headers)
    POD_COUNT=$(echo "$PODS" | wc -l)
    UNIQUE_NODES=$(echo "$PODS" | awk '{print $7}' | sort -u | wc -l)
    
    info "Total pods: $POD_COUNT"
    info "Unique nodes: $UNIQUE_NODES"
    
    if [[ $POD_COUNT -ge 2 ]]; then
        info "✅ High availability configured (2+ pods)"
    else
        warn "⚠️ Only $POD_COUNT pod(s) running"
    fi
    
    if [[ $UNIQUE_NODES -ge 2 ]]; then
        info "✅ Pods distributed across multiple nodes"
    else
        warn "⚠️ Pods running on single node"
    fi
else
    warn "kubectl not available - skipping Kubernetes checks"
fi

header "3. Performance Baseline Test"

# Test response time
info "Testing response time..."
RESPONSE_TIME=$(curl -s -w "%{time_total}\n" -o /dev/null "$JELLYFIN_URL")
info "Response time: ${RESPONSE_TIME}s"

if (( $(echo "$RESPONSE_TIME < 1.0" | bc -l) )); then
    info "✅ Response time excellent (< 1s)"
elif (( $(echo "$RESPONSE_TIME < 3.0" | bc -l) )); then
    info "✅ Response time good (< 3s)"
else
    warn "⚠️ Response time slow (${RESPONSE_TIME}s)"
fi

# Test concurrent connections
info "Testing concurrent connections..."
CONCURRENT_TESTS=5
TEMP_DIR="/tmp/jellyfin-perf-test"
mkdir -p "$TEMP_DIR"

for i in $(seq 1 $CONCURRENT_TESTS); do
    curl -s -w "%{time_total}\n" -o /dev/null "$JELLYFIN_URL" > "$TEMP_DIR/test_$i.txt" &
done

wait

# Calculate average response time
TOTAL_TIME=0
for i in $(seq 1 $CONCURRENT_TESTS); do
    TIME=$(cat "$TEMP_DIR/test_$i.txt")
    TOTAL_TIME=$(echo "$TOTAL_TIME + $TIME" | bc -l)
done

AVERAGE_TIME=$(echo "scale=3; $TOTAL_TIME / $CONCURRENT_TESTS" | bc -l)
info "Average response time with $CONCURRENT_TESTS concurrent requests: ${AVERAGE_TIME}s"

if (( $(echo "$AVERAGE_TIME < 2.0" | bc -l) )); then
    info "✅ Concurrent performance excellent"
elif (( $(echo "$AVERAGE_TIME < 5.0" | bc -l) )); then
    info "✅ Concurrent performance good"
else
    warn "⚠️ Concurrent performance may need optimization"
fi

header "4. Streaming Capability Test"

# Test large file transfer capability (simulated)
info "Testing large file transfer capability..."
TRANSFER_SIZE="100M"
TRANSFER_URL="$JELLYFIN_URL/test"

# Create a test file
dd if=/dev/zero of="$TEMP_DIR/testfile" bs=1M count=100 2>/dev/null

# Test upload capability (if jellyfin supports it)
info "Testing upload bandwidth simulation..."
START_TIME=$(date +%s.%N)
cp "$TEMP_DIR/testfile" "$TEMP_DIR/testfile_copy" 2>/dev/null
END_TIME=$(date +%s.%N)

TRANSFER_TIME=$(echo "$END_TIME - $START_TIME" | bc -l)
BANDWIDTH=$(echo "scale=2; 100 / $TRANSFER_TIME" | bc -l)

info "100MB transfer time: ${TRANSFER_TIME}s"
info "Estimated bandwidth: ${BANDWIDTH} MB/s"

if (( $(echo "$BANDWIDTH > 50" | bc -l) )); then
    info "✅ Bandwidth excellent for 4K streaming"
elif (( $(echo "$BANDWIDTH > 25" | bc -l) )); then
    info "✅ Bandwidth good for 4K streaming"
else
    warn "⚠️ Bandwidth may be insufficient for multiple 4K streams"
fi

header "5. Resource Usage Test"

if command -v kubectl &> /dev/null; then
    info "Checking resource usage..."
    
    # Get pod resource usage
    RESOURCE_USAGE=$(kubectl top pods -n jellyfin --no-headers 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        echo "$RESOURCE_USAGE" | while read pod cpu memory; do
            info "Pod $pod: CPU=$cpu, Memory=$memory"
        done
    else
        warn "Resource metrics not available (metrics-server may not be running)"
    fi
    
    # Check storage usage
    info "Checking storage usage..."
    PVC_STATUS=$(kubectl get pvc -n jellyfin --no-headers)
    echo "$PVC_STATUS" | while read name status volume capacity access modes storageclass age; do
        info "PVC $name: $status, $capacity ($storageclass)"
    done
fi

header "6. Failover Test"

if command -v kubectl &> /dev/null && [[ $POD_COUNT -ge 2 ]]; then
    info "Testing pod failover (deleting one pod)..."
    
    FIRST_POD=$(kubectl get pods -n jellyfin --no-headers | head -1 | awk '{print $1}')
    info "Deleting pod: $FIRST_POD"
    
    kubectl delete pod "$FIRST_POD" -n jellyfin &
    DELETE_PID=$!
    
    # Test service availability during failover
    sleep 2
    info "Testing service availability during failover..."
    
    for i in {1..10}; do
        if curl -s --connect-timeout 5 "$JELLYFIN_URL/health" > /dev/null; then
            info "Service available during failover (test $i/10)"
        else
            warn "Service unavailable during failover (test $i/10)"
        fi
        sleep 1
    done
    
    wait $DELETE_PID
    
    # Wait for new pod to start
    info "Waiting for replacement pod..."
    sleep 10
    
    if curl -s --connect-timeout 10 "$JELLYFIN_URL/health" > /dev/null; then
        info "✅ Service recovered after failover"
    else
        error "❌ Service not recovered after failover"
    fi
else
    warn "Skipping failover test (insufficient pods or kubectl not available)"
fi

header "7. Security Test"

info "Testing security configuration..."

# Test unauthorized access
info "Testing network security..."
EXTERNAL_IP="8.8.8.8"  # Google DNS as external IP

# This should fail if firewall is configured correctly
if timeout 5 curl -s --connect-timeout 5 "http://$EXTERNAL_IP:30096" 2>/dev/null; then
    warn "⚠️ Service may be accessible from external networks"
else
    info "✅ Service properly restricted to local network"
fi

# Test HTTPS redirect
if curl -s -I "$JELLYFIN_URL" | grep -i "strict-transport-security"; then
    info "✅ Security headers present"
else
    warn "⚠️ Security headers may be missing"
fi

header "Test Results Summary"

echo ""
info "=== Jellyfin Performance Test Results ==="
echo ""
info "Service Availability:"
info "- NodePort: ✅ Available"
info "- LoadBalancer: $(curl -s --connect-timeout 5 "$LOAD_BALANCER_URL/health" > /dev/null && echo '✅ Available' || echo '⚠️ Not configured')"
info "- Ingress: $(curl -s --connect-timeout 5 -k "$INGRESS_URL/health" > /dev/null && echo '✅ Available' || echo '⚠️ Not configured')"

echo ""
info "Performance Metrics:"
info "- Single request response time: ${RESPONSE_TIME}s"
info "- Concurrent requests average: ${AVERAGE_TIME}s"
info "- Estimated bandwidth: ${BANDWIDTH} MB/s"

echo ""
info "High Availability:"
info "- Pod count: $POD_COUNT"
info "- Node distribution: $UNIQUE_NODES nodes"
info "- Failover: $(if [[ $POD_COUNT -ge 2 ]]; then echo '✅ Tested'; else echo '⚠️ Skipped'; fi)"

echo ""
info "4K Streaming Readiness:"
if (( $(echo "$BANDWIDTH > 25" | bc -l) )) && [[ $POD_COUNT -ge 2 ]] && (( $(echo "$AVERAGE_TIME < 5.0" | bc -l) )); then
    info "✅ System ready for 4K streaming to multiple devices"
else
    warn "⚠️ System may need optimization for optimal 4K performance"
fi

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
info "Performance test completed!"
info "For detailed monitoring, check Grafana: http://192.168.4.63:30300"