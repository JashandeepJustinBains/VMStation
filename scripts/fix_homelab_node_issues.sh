#!/bin/bash

# Fix Homelab Node Networking Issues
# Addresses: Flannel CrashLoopBackOff, kube-proxy crashes, and CNI problems

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if we have kubectl access
if ! kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    exit 1
fi

echo "=== Homelab Node Issue Remediation ==="
echo "Timestamp: $(date)"
echo

# Step 0: Check for CNI bridge IP conflicts (common root cause)
info "Step 0: Checking for CNI bridge IP conflicts"

# Check for ContainerCreating pods which often indicate CNI issues
CONTAINER_CREATING_PODS=$(kubectl get pods --all-namespaces | grep "ContainerCreating" | wc -l)

if [ "$CONTAINER_CREATING_PODS" -gt 0 ]; then
    warn "Found $CONTAINER_CREATING_PODS pods stuck in ContainerCreating - checking for CNI bridge conflicts"
    
    # Check for the specific CNI bridge error in events
    CNI_BRIDGE_ERRORS=$(kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i "failed to set bridge addr.*cni0.*already has an IP address" | tail -1)
    
    if [ -n "$CNI_BRIDGE_ERRORS" ]; then
        error "CNI bridge IP conflict detected!"
        echo "Error: $CNI_BRIDGE_ERRORS"
        echo
        warn "Applying CNI bridge fix before proceeding with other fixes..."
        
        if [ -f "./scripts/fix_cni_bridge_conflict.sh" ]; then
            ./scripts/fix_cni_bridge_conflict.sh
            echo
            info "CNI bridge fix applied - continuing with remaining fixes..."
        else
            error "CNI bridge fix script not found - manual intervention required"
            echo "Please run: sudo ip link delete cni0 && sudo systemctl restart containerd"
            echo "Then restart flannel pods: kubectl delete pods -n kube-flannel --all"
        fi
    else
        info "No CNI bridge conflicts detected in recent events"
    fi
else
    info "No pods stuck in ContainerCreating"
fi

# Step 1: Identify problematic pods on homelab node
info "Step 1: Identifying problematic pods on homelab node"

HOMELAB_PROBLEMS=$(kubectl get pods --all-namespaces -o wide | grep "homelab" | grep -E "(CrashLoopBackOff|Error|Unknown)" || true)

if [ -n "$HOMELAB_PROBLEMS" ]; then
    echo "Problematic pods on homelab node:"
    echo "$HOMELAB_PROBLEMS"
else
    info "No obvious problematic pods found on homelab node"
fi

# Step 2: Check and fix flannel pod on homelab
info "Step 2: Fixing flannel pod issues on homelab"

# Check for both CrashLoopBackOff and Completed status (flannel should never complete)
FLANNEL_POD=$(kubectl get pods -n kube-flannel -o wide | grep "homelab" | grep -E "(CrashLoopBackOff|Completed)" | awk '{print $1}' | head -1)
FLANNEL_STATUS=$(kubectl get pods -n kube-flannel -o wide | grep "homelab" | awk '{print $3}' | head -1)

if [ -n "$FLANNEL_POD" ]; then
    warn "Found problematic flannel pod: $FLANNEL_POD (Status: $FLANNEL_STATUS)"
    if [ "$FLANNEL_STATUS" = "Completed" ]; then
        warn "Flannel pod completed instead of running continuously - this indicates a configuration issue"
    fi
    
    warn "Deleting problematic flannel pod: $FLANNEL_POD"
    kubectl delete pod -n kube-flannel "$FLANNEL_POD" --force --grace-period=0
    
    echo "Waiting for flannel to recreate..."
    sleep 15
    
    # Check if new pod is running
    for i in {1..6}; do
        NEW_FLANNEL_STATUS=$(kubectl get pods -n kube-flannel -o wide | grep "homelab" | awk '{print $3}' | head -1)
        if [ "$NEW_FLANNEL_STATUS" = "Running" ]; then
            info "✓ Flannel pod on homelab is now running"
            break
        else
            echo "  Waiting for flannel pod... ($i/6) Status: $NEW_FLANNEL_STATUS"
            if [ "$NEW_FLANNEL_STATUS" = "Completed" ]; then
                warn "Flannel completed again - may need CNI configuration fix"
            fi
            sleep 10
        fi
    done
else
    # Still check if flannel is actually running properly
    if [ "$FLANNEL_STATUS" = "Running" ]; then
        info "✓ Flannel pod on homelab is running"
    elif [ -z "$FLANNEL_STATUS" ]; then
        warn "No flannel pod found on homelab node"
    else
        info "Flannel pod status on homelab: $FLANNEL_STATUS"
    fi
fi

# Step 3: Check and fix kube-proxy on homelab
info "Step 3: Fixing kube-proxy issues on homelab"

PROXY_POD=$(kubectl get pods -n kube-system -o wide | grep "kube-proxy" | grep "homelab" | grep "CrashLoopBackOff" | awk '{print $1}' | head -1)

if [ -n "$PROXY_POD" ]; then
    warn "Found crashlooping kube-proxy pod: $PROXY_POD"
    
    # Get logs to understand the crash reason
    echo "Analyzing kube-proxy crash logs..."
    CRASH_LOGS=$(kubectl logs -n kube-system "$PROXY_POD" --previous --tail=20 2>/dev/null || echo "No previous logs available")
    echo "Recent crash logs:"
    echo "$CRASH_LOGS"
    
    # Check for specific error patterns
    if echo "$CRASH_LOGS" | grep -qi "iptables.*failed\|nftables.*incompatible"; then
        warn "Detected iptables/nftables compatibility issues"
        # May need to apply compatibility fixes first
    fi
    
    warn "Deleting crashlooping kube-proxy pod: $PROXY_POD"
    kubectl delete pod -n kube-system "$PROXY_POD" --force --grace-period=0
    
    echo "Waiting for kube-proxy to recreate..."
    sleep 15
    
    # Check if new pod is running with more patience for networking issues
    for i in {1..10}; do
        NEW_PROXY_STATUS=$(kubectl get pods -n kube-system -o wide | grep "kube-proxy" | grep "homelab" | awk '{print $3}' | head -1)
        if [ "$NEW_PROXY_STATUS" = "Running" ]; then
            info "✓ kube-proxy pod on homelab is now running"
            break
        elif [ "$NEW_PROXY_STATUS" = "CrashLoopBackOff" ]; then
            if [ "$i" -ge 5 ]; then
                warn "kube-proxy still crashing after $i attempts - may need additional intervention"
                # Get the new pod name and check logs again
                NEW_PROXY_POD=$(kubectl get pods -n kube-system -o wide | grep "kube-proxy" | grep "homelab" | awk '{print $1}' | head -1)
                if [ -n "$NEW_PROXY_POD" ]; then
                    echo "New crash logs:"
                    kubectl logs -n kube-system "$NEW_PROXY_POD" --previous --tail=10 2>/dev/null || echo "No new logs available"
                fi
            fi
            echo "  kube-proxy still crashing... ($i/10) Status: $NEW_PROXY_STATUS"
            sleep 15
        else
            echo "  Waiting for kube-proxy pod... ($i/10) Status: $NEW_PROXY_STATUS"
            sleep 10
        fi
    done
else
    # Check if kube-proxy exists and is running
    PROXY_STATUS=$(kubectl get pods -n kube-system -o wide | grep "kube-proxy" | grep "homelab" | awk '{print $3}' | head -1)
    if [ "$PROXY_STATUS" = "Running" ]; then
        info "✓ kube-proxy pod on homelab is running"
    elif [ -z "$PROXY_STATUS" ]; then
        warn "No kube-proxy pod found on homelab node"
    else
        info "kube-proxy pod status on homelab: $PROXY_STATUS"
    fi
fi

# Step 4: Fix CoreDNS scheduling to prefer masternode
info "Step 4: Fixing CoreDNS scheduling preferences"

# Check current CoreDNS deployment
COREDNS_ON_HOMELAB=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide | grep "homelab" || true)

if [ -n "$COREDNS_ON_HOMELAB" ]; then
    warn "CoreDNS is running on homelab - will patch deployment to prefer masternode"
    
    # Patch CoreDNS deployment to prefer control-plane nodes
    kubectl patch deployment coredns -n kube-system -p '{
        "spec": {
            "template": {
                "spec": {
                    "affinity": {
                        "nodeAffinity": {
                            "preferredDuringSchedulingIgnoredDuringExecution": [{
                                "weight": 100,
                                "preference": {
                                    "matchExpressions": [{
                                        "key": "node-role.kubernetes.io/control-plane",
                                        "operator": "Exists"
                                    }]
                                }
                            }]
                        }
                    },
                    "tolerations": [{
                        "key": "node-role.kubernetes.io/control-plane",
                        "operator": "Exists",
                        "effect": "NoSchedule"
                    }]
                }
            }
        }
    }'
    
    # Force CoreDNS pod restart to apply scheduling changes
    echo "Restarting CoreDNS deployment..."
    kubectl rollout restart deployment/coredns -n kube-system
    
    echo "Waiting for CoreDNS to reschedule..."
    kubectl rollout status deployment/coredns -n kube-system --timeout=120s
    
else
    info "CoreDNS is not running on homelab node"
fi

# Step 5: Clean up any stuck pods on masternode that might be waiting for network
info "Step 5: Restarting stuck ContainerCreating pods"

STUCK_PODS=$(kubectl get pods --all-namespaces | grep "ContainerCreating" | awk '{print $2 " " $1}' || true)

if [ -n "$STUCK_PODS" ]; then
    echo "Found stuck ContainerCreating pods:"
    echo "$STUCK_PODS"
    echo
    
    # Delete stuck pods to force recreation
    echo "$STUCK_PODS" | while read pod namespace; do
        if [ -n "$pod" ] && [ -n "$namespace" ]; then
            warn "Deleting stuck pod: $namespace/$pod"
            kubectl delete pod -n "$namespace" "$pod" --force --grace-period=0 || true
        fi
    done
    
    echo "Waiting for pods to recreate..."
    sleep 30
fi

# Step 6: Verify cluster health
info "Step 6: Verifying cluster health after fixes"

echo "=== Cluster Status After Fixes ==="
kubectl get nodes -o wide

echo
echo "=== Critical Pod Status ==="
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
kubectl get pods -n kube-flannel -o wide
kubectl get pods -n kube-system -l component=kube-proxy -o wide

echo
echo "=== Monitoring Pod Status ==="
kubectl get pods -n monitoring -o wide 2>/dev/null || echo "No monitoring namespace yet"

# Step 7: Test DNS resolution
info "Step 7: Testing DNS resolution"

kubectl run dns-test --image=busybox:1.28 --rm -it --restart=Never -- nslookup kubernetes.default &
DNS_TEST_PID=$!

# Wait up to 30 seconds for DNS test
sleep 5
if kill -0 $DNS_TEST_PID 2>/dev/null; then
    # Test is still running, kill it
    kill $DNS_TEST_PID 2>/dev/null || true
    warn "DNS test timed out - may indicate ongoing DNS issues"
else
    info "✓ DNS resolution test completed"
fi

echo
info "=== Homelab Node Issue Remediation Complete ==="

# Final status check
REMAINING_ISSUES=$(kubectl get pods --all-namespaces | grep -E "(CrashLoopBackOff|Error|Unknown)" | grep -v "Completed" | wc -l)
COMPLETED_FLANNEL=$(kubectl get pods -n kube-flannel | grep "Completed" | wc -l)

if [ "$REMAINING_ISSUES" -eq 0 ] && [ "$COMPLETED_FLANNEL" -eq 0 ]; then
    info "✅ No remaining crashlooping or problematic pods detected"
    echo "Cluster networking should now be stable for application deployment."
elif [ "$COMPLETED_FLANNEL" -gt 0 ]; then
    warn "⚠️  Found $COMPLETED_FLANNEL flannel pods in Completed state - this indicates CNI configuration issues"
    kubectl get pods -n kube-flannel | grep "Completed"
    echo "Flannel pods should be Running continuously. Consider running the CNI bridge fix script."
else
    warn "⚠️  $REMAINING_ISSUES pods still have issues - running additional fixes"
    
    # Run the additional pod fixes if available
    if [ -f "./scripts/fix_remaining_pod_issues.sh" ]; then
        echo
        info "Running additional pod issue fixes..."
        ./scripts/fix_remaining_pod_issues.sh
    else
        echo "Check with: kubectl get pods --all-namespaces | grep -E '(CrashLoopBackOff|Error|Unknown)'"
    fi
fi

echo
echo "Next steps:"
echo "1. Monitor flannel and CoreDNS stability: kubectl get pods -n kube-system -l k8s-app=kube-dns"
echo "2. Wait a few minutes for any remaining pods to stabilize"
echo "3. Check Jellyfin status: kubectl get pods -n jellyfin -o wide"
echo "4. If Jellyfin shows 0/1 ready, run: ./scripts/fix_remaining_pod_issues.sh"
echo "5. Access Jellyfin at: http://192.168.4.61:30096 (once ready)"