#!/bin/bash

# Fix Remaining VMStation Pod Issues
# Addresses specific problems after deploy.sh and fix_homelab_node_issues.sh
# Focuses on: jellyfin readiness issues and kube-proxy crashloop

set -e

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

echo "=== VMStation Remaining Pod Issues Fix ==="
echo "Timestamp: $(date)"
echo

# Check if we have kubectl access
if ! timeout 30 kubectl get nodes >/dev/null 2>&1; then
    error "Cannot access Kubernetes cluster"
    echo "Please ensure this script is run from the control plane node"
    exit 1
fi

# Function to wait for pod readiness
wait_for_pod() {
    local namespace="$1"
    local pod_name="$2"
    local timeout="${3:-300}"
    
    info "Waiting for pod $namespace/$pod_name to be ready (timeout: ${timeout}s)"
    
    for i in $(seq 1 $timeout); do
        if kubectl get pod -n "$namespace" "$pod_name" >/dev/null 2>&1; then
            local status=$(kubectl get pod -n "$namespace" "$pod_name" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            local ready=$(kubectl get pod -n "$namespace" "$pod_name" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
            
            if [ "$status" = "Running" ] && [ "$ready" = "true" ]; then
                info "✓ Pod $namespace/$pod_name is ready"
                return 0
            fi
            
            if [ $((i % 30)) -eq 0 ]; then
                echo "  Still waiting... Status: $status, Ready: $ready ($i/${timeout}s)"
            fi
        fi
        sleep 1
    done
    
    warn "Timeout waiting for pod $namespace/$pod_name"
    return 1
}

info "Step 1: Fix Jellyfin readiness probe issues"

# Check if jellyfin pod exists
if kubectl get pod -n jellyfin jellyfin >/dev/null 2>&1; then
    
    # Get current jellyfin status
    JELLYFIN_READY=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    JELLYFIN_RESTARTS=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0")
    
    echo "Current jellyfin status: Ready=$JELLYFIN_READY, Restarts=$JELLYFIN_RESTARTS"
    
    if [ "$JELLYFIN_READY" = "false" ] || [ "$JELLYFIN_RESTARTS" -gt 5 ]; then
        warn "Jellyfin pod has readiness issues - applying fixes"
        
        # First, check if the directories exist and have correct permissions
        info "Ensuring jellyfin volume directories exist with correct permissions"
        
        # Create media directory if it doesn't exist
        if [ ! -d "/srv/media" ]; then
            sudo mkdir -p /srv/media
            sudo chown 1000:1000 /srv/media
            sudo chmod 755 /srv/media
            info "Created /srv/media directory"
        else
            # Fix permissions if they're wrong
            sudo chown 1000:1000 /srv/media
            sudo chmod 755 /srv/media
            debug "Fixed /srv/media permissions"
        fi
        
        # Create config directory if it doesn't exist
        if [ ! -d "/var/lib/jellyfin" ]; then
            sudo mkdir -p /var/lib/jellyfin
            sudo chown 1000:1000 /var/lib/jellyfin
            sudo chmod 755 /var/lib/jellyfin
            info "Created /var/lib/jellyfin directory"
        else
            # Fix permissions if they're wrong
            sudo chown 1000:1000 /var/lib/jellyfin
            sudo chmod 755 /var/lib/jellyfin
            debug "Fixed /var/lib/jellyfin permissions"
        fi
        
        # Clean up any existing Jellyfin resources that might conflict
        info "Cleaning up existing Jellyfin resources to prevent conflicts"
        kubectl delete service -n jellyfin jellyfin-service --ignore-not-found=true || true
        kubectl delete service -n jellyfin jellyfin --ignore-not-found=true || true
        kubectl delete deployment -n jellyfin jellyfin --ignore-not-found=true || true
        kubectl delete pod -n jellyfin jellyfin --ignore-not-found=true || true
        sleep 5  # Give time for resources to be cleaned up
        
        # Update jellyfin pod with improved health checks
        info "Updating jellyfin pod configuration with improved health checks"
        
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: jellyfin
  namespace: jellyfin
  labels:
    app: jellyfin
    component: media-server
spec:
  nodeSelector:
    kubernetes.io/hostname: storagenodet3500
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  containers:
  - name: jellyfin
    image: jellyfin/jellyfin:latest
    imagePullPolicy: IfNotPresent
    ports:
    - name: http
      containerPort: 8096
      protocol: TCP
    - name: https
      containerPort: 8920
      protocol: TCP
    env:
    - name: JELLYFIN_PublishedServerUrl
      value: "http://192.168.4.61:30096"
    resources:
      requests:
        memory: "512Mi"
        cpu: "200m"
      limits:
        memory: "2Gi"
        cpu: "1000m"
    volumeMounts:
    - name: media
      mountPath: /media
      readOnly: true
    - name: config
      mountPath: /config
      readOnly: false
    # Improved health checks using root endpoint for compatibility
    livenessProbe:
      httpGet:
        path: /
        port: 8096
        scheme: HTTP
      initialDelaySeconds: 180
      periodSeconds: 60
      timeoutSeconds: 30
      failureThreshold: 5
    readinessProbe:
      httpGet:
        path: /
        port: 8096
        scheme: HTTP
      initialDelaySeconds: 120
      periodSeconds: 30
      timeoutSeconds: 15
      failureThreshold: 5
    # Startup probe to handle slow initialization
    startupProbe:
      httpGet:
        path: /
        port: 8096
        scheme: HTTP
      initialDelaySeconds: 60
      periodSeconds: 15
      timeoutSeconds: 10
      failureThreshold: 20
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: false
      capabilities:
        drop:
        - ALL
  volumes:
  - name: media
    hostPath:
      path: /srv/media
      type: DirectoryOrCreate
  - name: config
    hostPath:
      path: /var/lib/jellyfin
      type: DirectoryOrCreate
  restartPolicy: Always
EOF
        
        # Also ensure the service exists (in case it was cleaned up)
        info "Ensuring Jellyfin service exists"
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: jellyfin-service
  namespace: jellyfin
  labels:
    app: jellyfin
    component: media-server
spec:
  type: NodePort
  ports:
  - port: 8096
    targetPort: 8096
    nodePort: 30096
    name: http
  - port: 8920
    targetPort: 8920
    nodePort: 30920
    name: https
  selector:
    app: jellyfin
    component: media-server
EOF
        
        # Wait for the pod to be recreated and become ready
        sleep 10
        wait_for_pod jellyfin jellyfin 300
        
    else
        info "Jellyfin pod appears to be healthy"
    fi
else
    warn "Jellyfin pod not found - may need to be deployed first"
fi

echo
info "Step 2: Fix kube-proxy CrashLoopBackOff and iptables compatibility issues"

# Function to check and fix iptables/nftables compatibility
fix_iptables_compatibility() {
    info "Checking iptables/nftables compatibility on cluster nodes"
    
    # Check if we're experiencing nftables compatibility issues
    local iptables_error=$(kubectl logs -n kube-system -l component=kube-proxy --tail=100 2>/dev/null | grep -i "nf_tables.*incompatible" | head -1 || echo "")
    
    if [ -n "$iptables_error" ]; then
        warn "Detected iptables/nftables compatibility issue:"
        echo "$iptables_error"
        
        info "Applying iptables compatibility fix to kube-proxy configuration"
        
        # Get current kube-proxy configmap
        if kubectl get configmap kube-proxy -n kube-system >/dev/null 2>&1; then
            # Patch the kube-proxy configmap to use iptables mode explicitly
            info "Updating kube-proxy to use legacy iptables mode"
            
            # Create a patch for the configmap
            kubectl patch configmap kube-proxy -n kube-system --patch '{
                "data": {
                    "config.conf": "apiVersion: kubeproxy.config.k8s.io/v1alpha1\nbindAddress: 0.0.0.0\nclientConnection:\n  acceptContentTypes: \"\"\n  burst: 10\n  contentType: application/vnd.kubernetes.protobuf\n  kubeconfig: /var/lib/kube-proxy/kubeconfig.conf\n  qps: 5\nclusterCIDR: \"10.244.0.0/16\"\nconfigSyncPeriod: 15m0s\nconntrack:\n  maxPerCore: 32768\n  min: 131072\n  tcpCloseWaitTimeout: 1h0m0s\n  tcpEstablishedTimeout: 24h0m0s\nenabledProfilingMode: false\nhealthzBindAddress: 0.0.0.0:10256\nhostnameOverride: \"\"\niptables:\n  masqueradeAll: false\n  masqueradeBit: 14\n  minSyncPeriod: 0s\n  syncPeriod: 30s\nkind: KubeProxyConfiguration\nmetricsBindAddress: 127.0.0.1:10249\nmode: \"iptables\"\nnodePortAddresses: null\noomscoreadj: -999\nportRange: \"\"\nresourceContainer: /kube-proxy\nudpIdleTimeout: 250ms\nwinkernel:\n  enableDSR: false\n  networkName: \"\"\n  sourceVip: \"\""
                }
            }' || warn "Failed to patch kube-proxy configmap"
            
        else
            warn "kube-proxy configmap not found - creating basic configuration"
            
            # Create a basic kube-proxy configmap with iptables mode
            cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-proxy
  namespace: kube-system
data:
  config.conf: |
    apiVersion: kubeproxy.config.k8s.io/v1alpha1
    kind: KubeProxyConfiguration
    mode: "iptables"
    clusterCIDR: "10.244.0.0/16"
    iptables:
      minSyncPeriod: 0s
      syncPeriod: 30s
    healthzBindAddress: 0.0.0.0:10256
    metricsBindAddress: 127.0.0.1:10249
EOF
        fi
    else
        info "No iptables/nftables compatibility issues detected in logs"
    fi
}

# Find crashlooping kube-proxy pods (check all nodes, not just homelab)
CRASHLOOP_PROXY=$(kubectl get pods -n kube-system -l component=kube-proxy -o wide | grep "CrashLoopBackOff" || echo "")

if [ -n "$CRASHLOOP_PROXY" ]; then
    warn "Found crashlooping kube-proxy pods:"
    echo "$CRASHLOOP_PROXY"
    
    # Get the first crashlooping pod for log analysis
    PROXY_POD=$(echo "$CRASHLOOP_PROXY" | head -1 | awk '{print $1}')
    PROXY_NODE=$(echo "$CRASHLOOP_PROXY" | head -1 | awk '{print $7}')
    
    warn "Analyzing logs from crashlooping kube-proxy pod: $PROXY_POD on node $PROXY_NODE"
    
    # Get logs to understand the issue
    echo "Getting logs from crashlooping kube-proxy..."
    kubectl logs -n kube-system "$PROXY_POD" --previous --tail=50 2>/dev/null | head -20 || echo "No previous logs available"
    
    # Check for specific error patterns
    local nftables_error=$(kubectl logs -n kube-system "$PROXY_POD" --previous --tail=50 2>/dev/null | grep -i "nf_tables.*incompatible" || echo "")
    local iptables_error=$(kubectl logs -n kube-system "$PROXY_POD" --previous --tail=50 2>/dev/null | grep -i "iptables.*failed" || echo "")
    
    if [ -n "$nftables_error" ]; then
        error "Detected nftables compatibility issue: $nftables_error"
        fix_iptables_compatibility
    elif [ -n "$iptables_error" ]; then
        error "Detected iptables issue: $iptables_error"
        fix_iptables_compatibility
    fi
    
    # Common fixes for kube-proxy issues
    info "Applying kube-proxy fixes for affected nodes"
    
    # Delete all crashlooping pods to force recreation
    echo "$CRASHLOOP_PROXY" | while read line; do
        local pod_name=$(echo "$line" | awk '{print $1}')
        info "Deleting crashlooping pod: $pod_name"
        kubectl delete pod -n kube-system "$pod_name" --force --grace-period=0 2>/dev/null || true
    done
    
    echo "Waiting for new kube-proxy pods to start..."
    sleep 15
    
    # Restart kube-proxy daemonset to ensure clean state with new configuration
    info "Restarting kube-proxy daemonset with updated configuration"
    kubectl rollout restart daemonset/kube-proxy -n kube-system
    
    # Wait for rollout to complete
    if timeout 180 kubectl rollout status daemonset/kube-proxy -n kube-system; then
        info "✓ kube-proxy daemonset rollout completed"
    else
        warn "kube-proxy rollout timed out"
    fi
    
    # Check the new pod status
    sleep 10
    NEW_PROXY_STATUS=$(kubectl get pods -n kube-system -l component=kube-proxy -o wide)
    echo "Updated kube-proxy pod status:"
    echo "$NEW_PROXY_STATUS"
    
    # Count running vs total
    RUNNING_PROXY=$(echo "$NEW_PROXY_STATUS" | grep -c "Running" || echo "0")
    TOTAL_PROXY=$(echo "$NEW_PROXY_STATUS" | grep -c kube-proxy || echo "0")
    
    if [ "$RUNNING_PROXY" -eq "$TOTAL_PROXY" ] && [ "$TOTAL_PROXY" -gt 0 ]; then
        info "✓ All kube-proxy pods are now running ($RUNNING_PROXY/$TOTAL_PROXY)"
    else
        warn "Some kube-proxy pods still have issues ($RUNNING_PROXY/$TOTAL_PROXY running)"
        
        # Show any remaining problematic pods
        echo "$NEW_PROXY_STATUS" | grep -v "Running" | grep kube-proxy || true
    fi
    
else
    info "No crashlooping kube-proxy pods found"
    
    # Still check for iptables compatibility in current logs
    fix_iptables_compatibility
fi

echo
info "Step 3: Address any remaining CNI/networking issues"

# Check for any pods still stuck in ContainerCreating
STUCK_PODS=$(kubectl get pods --all-namespaces | grep "ContainerCreating" || echo "")

if [ -n "$STUCK_PODS" ]; then
    warn "Found pods stuck in ContainerCreating:"
    echo "$STUCK_PODS"
    
    # Apply the CNI bridge fix if needed
    if [ -f "./scripts/fix_cni_bridge_conflict.sh" ]; then
        info "Running CNI bridge conflict fix..."
        ./scripts/fix_cni_bridge_conflict.sh
    else
        warn "CNI bridge fix script not found - applying manual CNI reset"
        
        # Manual CNI reset
        sudo systemctl restart containerd
        kubectl delete pods -n kube-flannel --all --force --grace-period=0
        
        echo "Waiting for flannel to recreate..."
        sleep 30
        
        if timeout 120 kubectl rollout status daemonset/kube-flannel-ds -n kube-flannel; then
            info "✓ Flannel DaemonSet is ready"
        else
            warn "Flannel rollout timed out"
        fi
    fi
    
else
    info "No pods stuck in ContainerCreating"
fi

echo
info "Step 4: Restart any remaining problematic pods"

# Restart CoreDNS if it's not ready
COREDNS_READY=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | awk '{print $2}' | grep -c "1/1" || echo "0")
COREDNS_TOTAL=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | wc -l)

if [ "$COREDNS_READY" -lt "$COREDNS_TOTAL" ]; then
    warn "CoreDNS pods are not all ready ($COREDNS_READY/$COREDNS_TOTAL)"
    kubectl rollout restart deployment/coredns -n kube-system
    
    if timeout 120 kubectl rollout status deployment/coredns -n kube-system; then
        info "✓ CoreDNS restart completed"
    else
        warn "CoreDNS restart timed out"
    fi
fi

echo
info "Step 5: Final validation and cleanup"

echo "=== Final Cluster Status ==="
kubectl get nodes -o wide

echo
echo "=== Critical Pod Status ==="
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
kubectl get pods -n kube-flannel -o wide
kubectl get pods -n kube-system -l component=kube-proxy -o wide

if kubectl get namespace jellyfin >/dev/null 2>&1; then
    echo
    echo "=== Jellyfin Status ==="
    kubectl get pods -n jellyfin -o wide
fi

echo
echo "=== Monitoring Pods ==="
kubectl get pods -n monitoring -o wide 2>/dev/null || echo "No monitoring namespace found"

# Count remaining issues
REMAINING_CRASHLOOP=$(kubectl get pods --all-namespaces | grep -c "CrashLoopBackOff" || echo "0")
REMAINING_PENDING=$(kubectl get pods --all-namespaces | grep -c "Pending\|ContainerCreating" || echo "0")
JELLYFIN_FINAL_READY=$(kubectl get pod -n jellyfin jellyfin -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo "false")

echo
info "=== Fix Summary ==="

if [ "$JELLYFIN_FINAL_READY" = "true" ]; then
    info "✅ Jellyfin pod is now ready and healthy"
else
    warn "⚠️  Jellyfin pod still has readiness issues"
fi

if [ "$REMAINING_CRASHLOOP" -eq 0 ]; then
    info "✅ No pods in CrashLoopBackOff state"
else
    warn "⚠️  $REMAINING_CRASHLOOP pods still in CrashLoopBackOff"
fi

if [ "$REMAINING_PENDING" -eq 0 ]; then
    info "✅ No pods stuck in Pending/ContainerCreating"
else
    warn "⚠️  $REMAINING_PENDING pods still pending"
fi

if [ "$JELLYFIN_FINAL_READY" = "true" ] && [ "$REMAINING_CRASHLOOP" -eq 0 ] && [ "$REMAINING_PENDING" -eq 0 ]; then
    info "🎉 All critical issues have been resolved!"
    echo
    echo "Jellyfin should be accessible at: http://192.168.4.61:30096"
else
    warn "Some issues may persist. Check logs with:"
    echo "  kubectl logs -n jellyfin jellyfin"
    echo "  kubectl logs -n kube-system -l component=kube-proxy"
    echo "  kubectl get events --all-namespaces --sort-by='.lastTimestamp'"
fi

echo
echo "=== VMStation Pod Issues Fix Complete ==="