#!/bin/bash

# Validate cert-manager installation and health
# This script provides comprehensive cert-manager validation and troubleshooting

set -e

echo "=== cert-manager Validation and Health Check ==="
echo "Timestamp: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo "=== Phase 1: Pre-requisite Checks ==="

if ! command_exists kubectl; then
    echo -e "${RED}✗ kubectl not found${NC}"
    exit 1
else
    echo -e "${GREEN}✓ kubectl available${NC}"
fi

if ! command_exists helm; then
    echo -e "${RED}✗ helm not found${NC}"
    exit 1
else
    echo -e "${GREEN}✓ helm available${NC}"
fi

# Test kubectl connectivity
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}✗ kubectl cannot connect to cluster${NC}"
    exit 1
else
    echo -e "${GREEN}✓ kubectl connected to cluster${NC}"
fi

echo ""
echo "=== Phase 2: cert-manager Installation Status ==="

# Check if cert-manager namespace exists
if kubectl get namespace cert-manager >/dev/null 2>&1; then
    echo -e "${GREEN}✓ cert-manager namespace exists${NC}"
else
    echo -e "${RED}✗ cert-manager namespace missing${NC}"
    echo -e "${YELLOW}Run: kubectl create namespace cert-manager${NC}"
fi

# Check Helm release
echo -e "${BLUE}Checking Helm release status...${NC}"
helm_status=$(helm status cert-manager -n cert-manager 2>/dev/null || echo "NOT_FOUND")
if [ "$helm_status" != "NOT_FOUND" ]; then
    echo -e "${GREEN}✓ cert-manager Helm release found${NC}"
    helm status cert-manager -n cert-manager
else
    echo -e "${RED}✗ cert-manager Helm release not found${NC}"
fi

echo ""
echo "=== Phase 3: Deployment Status ==="

deployments=("cert-manager" "cert-manager-webhook" "cert-manager-cainjector")
all_ready=true

for deployment in "${deployments[@]}"; do
    echo -e "${BLUE}Checking deployment: $deployment${NC}"
    
    if kubectl get deployment "$deployment" -n cert-manager >/dev/null 2>&1; then
        ready_replicas=$(kubectl get deployment "$deployment" -n cert-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        desired_replicas=$(kubectl get deployment "$deployment" -n cert-manager -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
        
        if [ "$ready_replicas" = "$desired_replicas" ] && [ "$ready_replicas" != "0" ]; then
            echo -e "${GREEN}✓ $deployment: $ready_replicas/$desired_replicas replicas ready${NC}"
        else
            echo -e "${RED}✗ $deployment: $ready_replicas/$desired_replicas replicas ready${NC}"
            all_ready=false
        fi
    else
        echo -e "${RED}✗ $deployment: deployment not found${NC}"
        all_ready=false
    fi
done

echo ""
echo "=== Phase 4: Pod Status ==="

echo -e "${BLUE}cert-manager pods:${NC}"
kubectl get pods -n cert-manager -o wide 2>/dev/null || echo -e "${RED}Unable to get pod status${NC}"

# Check for failed pods
failed_pods=$(kubectl get pods -n cert-manager --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l)
if [ "$failed_pods" -gt 0 ]; then
    echo -e "${RED}Found $failed_pods non-running pods${NC}"
    echo -e "${YELLOW}Non-running pods:${NC}"
    kubectl get pods -n cert-manager --field-selector=status.phase!=Running
    all_ready=false
fi

echo ""
echo "=== Phase 5: Service Status ==="

services=("cert-manager" "cert-manager-webhook")
for service in "${services[@]}"; do
    if kubectl get service "$service" -n cert-manager >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Service $service exists${NC}"
    else
        echo -e "${RED}✗ Service $service missing${NC}"
        all_ready=false
    fi
done

echo ""
echo "=== Phase 6: CRD Status ==="

crds=("certificates.cert-manager.io" "certificaterequests.cert-manager.io" "issuers.cert-manager.io" "clusterissuers.cert-manager.io")
for crd in "${crds[@]}"; do
    if kubectl get crd "$crd" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ CRD $crd exists${NC}"
    else
        echo -e "${RED}✗ CRD $crd missing${NC}"
        all_ready=false
    fi
done

echo ""
echo "=== Phase 7: Functional Test ==="

echo -e "${BLUE}Testing cert-manager functionality with test issuer...${NC}"

# Create a test self-signed issuer
kubectl apply -f - <<EOF >/dev/null 2>&1 || true
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: test-selfsigned
  namespace: cert-manager
spec:
  selfSigned: {}
EOF

# Wait a moment for the issuer to be processed
sleep 5

# Check if the issuer is ready
if kubectl get issuer test-selfsigned -n cert-manager -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
    echo -e "${GREEN}✓ cert-manager functional test passed${NC}"
    # Clean up test issuer
    kubectl delete issuer test-selfsigned -n cert-manager >/dev/null 2>&1 || true
else
    echo -e "${RED}✗ cert-manager functional test failed${NC}"
    echo -e "${YELLOW}Issuer status:${NC}"
    kubectl describe issuer test-selfsigned -n cert-manager 2>/dev/null || echo "Unable to describe issuer"
    all_ready=false
fi

echo ""
echo "=== Phase 8: Recent Events ==="

echo -e "${BLUE}Recent cert-manager events:${NC}"
kubectl get events -n cert-manager --sort-by=.metadata.creationTimestamp | tail -10 || echo -e "${YELLOW}No events found${NC}"

echo ""
echo "=== Phase 9: Resource Usage ==="

echo -e "${BLUE}cert-manager resource usage:${NC}"
kubectl top pods -n cert-manager 2>/dev/null || echo -e "${YELLOW}Unable to get resource usage (metrics-server may not be available)${NC}"

echo ""
echo "=== Summary ==="

if [ "$all_ready" = true ]; then
    echo -e "${GREEN}✓ cert-manager validation PASSED - All components healthy!${NC}"
    echo ""
    echo "cert-manager is ready to issue certificates."
    echo "You can now create ClusterIssuers and Certificates."
    exit 0
else
    echo -e "${RED}✗ cert-manager validation FAILED - Issues detected${NC}"
    echo ""
    echo "=== Troubleshooting Steps ==="
    echo "1. Check pod logs:"
    echo "   kubectl logs -n cert-manager deployment/cert-manager"
    echo "   kubectl logs -n cert-manager deployment/cert-manager-webhook"
    echo "   kubectl logs -n cert-manager deployment/cert-manager-cainjector"
    echo ""
    echo "2. Check recent events:"
    echo "   kubectl get events -n cert-manager --sort-by=.metadata.creationTimestamp"
    echo ""
    echo "3. Describe problematic resources:"
    echo "   kubectl describe pods -n cert-manager"
    echo "   kubectl describe deployments -n cert-manager"
    echo ""
    echo "4. Reinstall cert-manager:"
    echo "   helm uninstall cert-manager -n cert-manager"
    echo "   kubectl delete namespace cert-manager"
    echo "   ./update_and_deploy.sh"
    exit 1
fi