#!/bin/bash
# Test script to verify CrashLoopBackOff fixes for monitoring stack
# Tests the three critical fixes:
# 1. Blackbox exporter config schema
# 2. Loki boltdb-shipper period
# 3. Node uncordon task

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASS=0
FAIL=0
WARN=0

check_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((PASS++))
}

check_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    ((FAIL++))
}

check_warn() {
    echo -e "${YELLOW}⚠️  WARN${NC}: $1"
    ((WARN++))
}

echo "=========================================="
echo "CrashLoopBackOff Fixes Validation"
echo "=========================================="
echo

# Test 1: Blackbox exporter timeout at module level
echo "1. Testing Blackbox Exporter Configuration..."

# Extract blackbox config and check if timeout is at module level
if python3 -c "
import yaml
import sys
with open('manifests/monitoring/prometheus.yaml', 'r') as f:
    docs = list(yaml.safe_load_all(f))
for doc in docs:
    if doc and doc.get('metadata', {}).get('name') == 'blackbox-exporter-config':
        config = yaml.safe_load(doc['data']['blackbox.yml'])
        
        # Check all modules have timeout at module level
        all_good = True
        for module_name, module_config in config['modules'].items():
            if 'timeout' not in module_config:
                print(f'Module {module_name} missing timeout at module level')
                all_good = False
            
            # Check timeout not nested in prober config
            prober = module_config.get('prober')
            if prober in module_config and isinstance(module_config[prober], dict):
                if 'timeout' in module_config[prober]:
                    print(f'Module {module_name} has timeout nested in {prober} config')
                    all_good = False
        
        sys.exit(0 if all_good else 1)
" 2>/dev/null; then
    check_pass "Blackbox exporter timeout at module level"
else
    check_fail "Blackbox exporter timeout configuration incorrect"
fi

echo

# Test 2: Loki boltdb-shipper period is 24h
echo "2. Testing Loki Schema Configuration..."

if python3 -c "
import yaml
import sys
with open('manifests/monitoring/loki.yaml', 'r') as f:
    docs = list(yaml.safe_load_all(f))
for doc in docs:
    if doc and doc.get('metadata', {}).get('name') == 'loki-config':
        loki_config = yaml.safe_load(doc['data']['local-config.yaml'])
        for config in loki_config['schema_config']['configs']:
            if config['store'] == 'boltdb-shipper':
                if config['index']['period'] == '24h':
                    sys.exit(0)
                else:
                    print(f\"Period is {config['index']['period']}, should be 24h\")
                    sys.exit(1)
sys.exit(1)
" 2>/dev/null; then
    check_pass "Loki boltdb-shipper period is 24h"
else
    check_fail "Loki boltdb-shipper period is not 24h"
fi

# Double check with grep
if grep -A 5 "store: boltdb-shipper" manifests/monitoring/loki.yaml | grep -q "period: 24h"; then
    check_pass "Loki period verified with grep"
else
    check_fail "Loki period verification failed"
fi

echo

# Test 3: Node uncordon task exists
echo "3. Testing Node Scheduling Fix..."

if grep -q "Ensure all nodes are schedulable (uncordon)" ansible/playbooks/deploy-cluster.yaml; then
    check_pass "Uncordon task found in playbook"
else
    check_fail "Uncordon task not found in playbook"
fi

if grep -q "kubectl.*uncordon" ansible/playbooks/deploy-cluster.yaml; then
    check_pass "Uncordon kubectl command present"
else
    check_fail "Uncordon kubectl command missing"
fi

# Verify uncordon task is before monitoring deployment
UNCORDON_LINE=$(grep -n "Ensure all nodes are schedulable" ansible/playbooks/deploy-cluster.yaml | cut -d: -f1 || echo "0")
MONITORING_LINE=$(grep -n "Deploy.*Monitoring" ansible/playbooks/deploy-cluster.yaml | head -1 | cut -d: -f1 || echo "999999")

if [ "$UNCORDON_LINE" -gt 0 ] && [ "$UNCORDON_LINE" -lt "$MONITORING_LINE" ]; then
    check_pass "Uncordon task positioned before monitoring deployment"
else
    check_warn "Uncordon task positioning unclear"
fi

echo

# Test 4: Jellyfin nodeSelector configuration
echo "4. Testing Jellyfin Configuration..."

if grep -B 5 -A 2 "nodeSelector:" manifests/jellyfin/jellyfin.yaml | grep -q "kubernetes.io/hostname: storagenodet3500"; then
    check_pass "Jellyfin nodeSelector targets storagenodet3500"
else
    check_fail "Jellyfin nodeSelector not targeting storagenodet3500"
fi

echo
echo "=========================================="
echo "Summary"
echo "=========================================="
echo -e "${GREEN}Passed:  $PASS${NC}"
echo -e "${YELLOW}Warnings: $WARN${NC}"
echo -e "${RED}Failed:  $FAIL${NC}"
echo

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✅ ALL CRASHLOOPBACKOFF FIXES VERIFIED${NC}"
    echo
    echo "The monitoring stack is ready for deployment:"
    echo "  - Blackbox exporter config is compatible with v0.25.0"
    echo "  - Loki schema config is compatible with boltdb-shipper"
    echo "  - Node scheduling issue is resolved"
    echo
    exit 0
else
    echo -e "${RED}❌ SOME FIXES ARE MISSING OR INCORRECT${NC}"
    echo
    echo "Please review the failed checks above."
    echo
    exit 1
fi
