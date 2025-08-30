#!/bin/bash
# Validation script for Kubernetes Dashboard and Drone CI/CD deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 VMStation Dashboard & Drone CI/CD Validation${NC}"
echo "================================================"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please install kubectl.${NC}"
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster.${NC}"
    echo "Ensure kubeconfig is properly configured."
    exit 1
fi

echo -e "${GREEN}✅ Kubernetes cluster connectivity verified${NC}"

# Function to check namespace exists
check_namespace() {
    local namespace=$1
    if kubectl get namespace "$namespace" &> /dev/null; then
        echo -e "${GREEN}✅ Namespace '$namespace' exists${NC}"
        return 0
    else
        echo -e "${RED}❌ Namespace '$namespace' not found${NC}"
        return 1
    fi
}

# Function to check pods in namespace
check_pods() {
    local namespace=$1
    local service_name=$2
    
    echo -e "${BLUE}Checking pods in namespace '$namespace' for '$service_name':${NC}"
    
    if ! kubectl get pods -n "$namespace" &> /dev/null; then
        echo -e "${RED}❌ Cannot access namespace '$namespace'${NC}"
        return 1
    fi
    
    local pod_count=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
    if [ "$pod_count" -eq 0 ]; then
        echo -e "${YELLOW}⚠️  No pods found in namespace '$namespace'${NC}"
        return 1
    fi
    
    # Check pod status
    local ready_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep "Running" | wc -l)
    local total_pods=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
    
    echo -e "   📊 Pods: $ready_pods/$total_pods running"
    
    if [ "$ready_pods" -eq "$total_pods" ]; then
        echo -e "${GREEN}✅ All pods running in '$namespace'${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  Some pods not ready in '$namespace'${NC}"
        kubectl get pods -n "$namespace" --no-headers | grep -v "Running"
        return 1
    fi
}

# Function to check service endpoints
check_service() {
    local namespace=$1
    local service_name=$2
    local expected_port=$3
    
    if kubectl get service "$service_name" -n "$namespace" &> /dev/null; then
        local nodeport=$(kubectl get service "$service_name" -n "$namespace" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
        if [ -n "$nodeport" ]; then
            echo -e "${GREEN}✅ Service '$service_name' exposed on NodePort: $nodeport${NC}"
            if [ -n "$expected_port" ] && [ "$nodeport" != "$expected_port" ]; then
                echo -e "${YELLOW}⚠️  Expected port $expected_port, got $nodeport${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  Service '$service_name' exists but no NodePort found${NC}"
        fi
    else
        echo -e "${RED}❌ Service '$service_name' not found in namespace '$namespace'${NC}"
        return 1
    fi
}

# Main validation checks
echo ""
echo -e "${BLUE}🔧 Checking Kubernetes Dashboard...${NC}"

if check_namespace "kubernetes-dashboard"; then
    check_pods "kubernetes-dashboard" "Kubernetes Dashboard"
    check_service "kubernetes-dashboard" "kubernetes-dashboard" "30443"
    
    # Check for admin user token
    if kubectl get secret admin-user -n kubernetes-dashboard &> /dev/null; then
        echo -e "${GREEN}✅ Admin user secret exists${NC}"
        echo -e "${BLUE}💡 Get admin token with:${NC}"
        echo "   kubectl -n kubernetes-dashboard get secret admin-user -o jsonpath=\"{.data.token}\" | base64 -d"
    else
        echo -e "${YELLOW}⚠️  Admin user secret not found${NC}"
    fi
fi

echo ""
echo -e "${BLUE}🚀 Checking Drone CI/CD...${NC}"

if check_namespace "localhost.localdomain"; then
    check_pods "localhost.localdomain" "Drone CI/CD"
    
    # Check Gitea service
    check_service "localhost.localdomain" "gitea" "30300"
    
    # Check Drone server service
    check_service "localhost.localdomain" "drone-server" "30080"
    
    # Check for PVCs
    local pvc_count=$(kubectl get pvc -n localhost.localdomain --no-headers 2>/dev/null | wc -l)
    if [ "$pvc_count" -gt 0 ]; then
        echo -e "${GREEN}✅ $pvc_count PVC(s) found for persistent storage${NC}"
    else
        echo -e "${YELLOW}⚠️  No PVCs found for persistent storage${NC}"
    fi
fi

echo ""
echo -e "${BLUE}📊 Checking Monitoring Integration...${NC}"

if check_namespace "monitoring"; then
    # Check ServiceMonitors
    local servicemonitors=$(kubectl get servicemonitor -n monitoring --no-headers 2>/dev/null | grep -E "(kubernetes-dashboard|drone-server)" | wc -l)
    if [ "$servicemonitors" -gt 0 ]; then
        echo -e "${GREEN}✅ ServiceMonitors configured for new services${NC}"
    else
        echo -e "${YELLOW}⚠️  ServiceMonitors not found for new services${NC}"
    fi
    
    # Check PrometheusRules
    local prometheusrules=$(kubectl get prometheusrule -n monitoring --no-headers 2>/dev/null | grep "drone-cicd-alerts" | wc -l)
    if [ "$prometheusrules" -gt 0 ]; then
        echo -e "${GREEN}✅ PrometheusRules configured for alerting${NC}"
    else
        echo -e "${YELLOW}⚠️  PrometheusRules not found for alerting${NC}"
    fi
    
    # Check Grafana dashboards
    local dashboards=$(kubectl get configmap -n monitoring --no-headers 2>/dev/null | grep -E "(kubernetes-dashboard-grafana|drone-cicd-grafana)" | wc -l)
    if [ "$dashboards" -gt 0 ]; then
        echo -e "${GREEN}✅ Grafana dashboards configured${NC}"
    else
        echo -e "${YELLOW}⚠️  Grafana dashboards not found${NC}"
    fi
fi

echo ""
echo -e "${BLUE}🌐 Service Access URLs${NC}"
echo "================================"

# Get node IPs
MONITORING_NODE_IP=$(kubectl get nodes -o jsonpath='{.items[?(@.metadata.labels.node-role\.kubernetes\.io/control-plane)].status.addresses[?(@.type=="InternalIP")].address}' | awk '{print $1}')
COMPUTE_NODE_IP=$(kubectl get nodes -o jsonpath='{.items[?(!@.metadata.labels.node-role\.kubernetes\.io/control-plane)].status.addresses[?(@.type=="InternalIP")].address}' | awk '{print $1}')

if [ -n "$MONITORING_NODE_IP" ]; then
    echo -e "${GREEN}📊 Grafana:${NC} http://$MONITORING_NODE_IP:30300"
    echo -e "${GREEN}🔧 Kubernetes Dashboard:${NC} https://$MONITORING_NODE_IP:30443"
fi

if [ -n "$COMPUTE_NODE_IP" ]; then
    echo -e "${GREEN}🚀 Drone CI/CD:${NC} http://$COMPUTE_NODE_IP:30080"
    echo -e "${GREEN}📝 Gitea:${NC} http://$COMPUTE_NODE_IP:30300"
fi

echo ""
echo -e "${BLUE}🔍 Validation Complete!${NC}"

# Summary
NAMESPACES_OK=0
if kubectl get namespace kubernetes-dashboard &> /dev/null; then ((NAMESPACES_OK++)); fi
if kubectl get namespace localhost.localdomain &> /dev/null; then ((NAMESPACES_OK++)); fi
if kubectl get namespace monitoring &> /dev/null; then ((NAMESPACES_OK++)); fi

echo -e "${GREEN}✅ $NAMESPACES_OK/3 namespaces found and accessible${NC}"

if [ "$NAMESPACES_OK" -eq 3 ]; then
    echo -e "${GREEN}🎉 All services appear to be deployed successfully!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  Some services may not be fully deployed. Check logs above.${NC}"
    exit 1
fi