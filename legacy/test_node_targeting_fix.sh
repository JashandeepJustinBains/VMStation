#!/bin/bash
# Test script for VMStation Node Targeting Fix
# Validates that components are scheduled on their intended nodes according to architecture

echo "=== Testing VMStation Node Targeting Configuration ==="

# Define expected node mappings based on VMStation architecture
EXPECTED_MONITORING_NODE="masternode"
EXPECTED_COMPUTE_NODE="r430computenode" 
EXPECTED_STORAGE_NODE="storagenodet3500"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test 1: Verify Drone CI deployment targets compute node
echo "Test 1: Checking Drone CI node targeting..."
if grep -q "apps_node: r430computenode" ansible/subsites/07-drone-ci.yaml; then
    echo -e "${GREEN}✅ Drone CI configured to target compute node (r430computenode)${NC}"
else
    echo -e "${RED}❌ Drone CI not properly configured for compute node${NC}"
    exit 1
fi

# Test 2: Verify cert-manager has monitoring node selectors
echo "Test 2: Checking cert-manager node targeting..."
if grep -A 10 "nodeSelector:" ansible/plays/kubernetes/setup_cert_manager.yaml | grep -q "node-role.vmstation.io/monitoring"; then
    echo -e "${GREEN}✅ cert-manager configured with monitoring node selectors${NC}"
else
    echo -e "${RED}❌ cert-manager missing monitoring node selectors${NC}"
    exit 1
fi

# Test 3: Verify cert-manager webhook has node selector
echo "Test 3: Checking cert-manager webhook node targeting..."
if grep -A 5 "webhook:" ansible/plays/kubernetes/setup_cert_manager.yaml | grep -A 3 "nodeSelector:" | grep -q "node-role.vmstation.io/monitoring"; then
    echo -e "${GREEN}✅ cert-manager webhook configured with monitoring node selector${NC}"
else
    echo -e "${RED}❌ cert-manager webhook missing monitoring node selector${NC}"
    exit 1
fi

# Test 4: Verify cert-manager cainjector has node selector  
echo "Test 4: Checking cert-manager cainjector node targeting..."
if grep -A 5 "cainjector:" ansible/plays/kubernetes/setup_cert_manager.yaml | grep -A 3 "nodeSelector:" | grep -q "node-role.vmstation.io/monitoring"; then
    echo -e "${GREEN}✅ cert-manager cainjector configured with monitoring node selector${NC}"
else
    echo -e "${RED}❌ cert-manager cainjector missing monitoring node selector${NC}"
    exit 1
fi

# Test 5: Verify cert-manager has node labeling logic
echo "Test 5: Checking cert-manager node labeling setup..."
if grep -q "Set up monitoring node labels for cert-manager targeting" ansible/plays/kubernetes/setup_cert_manager.yaml; then
    echo -e "${GREEN}✅ cert-manager playbook includes monitoring node labeling${NC}"
else
    echo -e "${RED}❌ cert-manager playbook missing monitoring node labeling${NC}"
    exit 1
fi

# Test 6: Verify monitoring deployment has proper node selector logic
echo "Test 6: Checking monitoring deployment node targeting..."
if grep -q "monitoring_node_selector.*node-role.vmstation.io/monitoring" ansible/plays/kubernetes/deploy_monitoring.yaml; then
    echo -e "${GREEN}✅ Monitoring deployment has proper node selector logic${NC}"
else
    echo -e "${RED}❌ Monitoring deployment missing proper node selector logic${NC}"
    exit 1
fi

# Test 7: Verify Jellyfin targets storage node (should already be correct)
echo "Test 7: Checking Jellyfin node targeting..."
if grep -q "nodeName: storagenodet3500" ansible/plays/kubernetes/jellyfin-minimal.yml; then
    echo -e "${GREEN}✅ Jellyfin correctly targets storage node (storagenodet3500)${NC}"
else
    echo -e "${RED}❌ Jellyfin not properly configured for storage node${NC}"
    exit 1
fi

# Test 8: Verify node labeling script exists for monitoring setup
echo "Test 8: Checking monitoring node labeling script..."
if [ -f "scripts/setup_monitoring_node_labels.sh" ]; then
    echo -e "${GREEN}✅ Monitoring node labeling script exists${NC}"
else
    echo -e "${RED}❌ Monitoring node labeling script missing${NC}"
    exit 1
fi

# Test 9: Verify monitoring node labeling script targets correct IPs
echo "Test 9: Checking monitoring node labeling script targets..."
if grep -q "MONITORING_NODE_IP=\"192.168.4.63\"" scripts/setup_monitoring_node_labels.sh; then
    echo -e "${GREEN}✅ Monitoring node labeling script targets masternode IP${NC}"
else
    echo -e "${RED}❌ Monitoring node labeling script doesn't target correct masternode IP${NC}"
    exit 1
fi

# Test 10: Verify homelab node is correctly identified in labeling script
echo "Test 10: Checking homelab node identification..."
if grep -q "HOMELAB_NODE_IP=\"192.168.4.62\"" scripts/setup_monitoring_node_labels.sh; then
    echo -e "${GREEN}✅ Homelab node correctly identified in labeling script${NC}"
else
    echo -e "${RED}❌ Homelab node not correctly identified in labeling script${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 All tests passed! Node targeting fix validated.${NC}"
echo ""
echo "Summary of changes:"
echo "- ✅ Drone CI targets compute node (r430computenode) at 192.168.4.62"
echo "- ✅ cert-manager components target monitoring nodes with proper selectors"
echo "- ✅ cert-manager playbook includes monitoring node labeling"
echo "- ✅ Monitoring stack uses label-based targeting for masternode"
echo "- ✅ Jellyfin continues to target storage node (storagenodet3500) at 192.168.4.61"
echo ""
echo "Expected deployment result:"
echo "- Masternode (192.168.4.63): monitoring stack + cert-manager + control-plane"
echo "- Compute node (192.168.4.62): Drone CI"
echo "- Storage node (192.168.4.61): Jellyfin"
echo "- All nodes: kube-proxy + node exporters"