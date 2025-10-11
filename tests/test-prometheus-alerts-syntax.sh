#!/bin/bash
# Test script to validate Prometheus alerts.yml YAML syntax
# This test ensures that the alerts.yml embedded in prometheus.yaml
# can be successfully parsed by YAML parsers and Prometheus

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================="
echo "Prometheus Alerts YAML Syntax Validator"
echo "========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_pass() {
    echo -e "${GREEN}✅ PASS:${NC} $1"
}

log_fail() {
    echo -e "${RED}❌ FAIL:${NC} $1"
    exit 1
}

log_info() {
    echo -e "${YELLOW}ℹ INFO:${NC} $1"
}

# Test 1: Check if Python3 and PyYAML are available
echo "[1/4] Checking prerequisites..."
if ! command -v python3 >/dev/null 2>&1; then
    log_fail "Python3 not found. Please install Python3."
fi
log_pass "Python3 found"

if ! python3 -c "import yaml" 2>/dev/null; then
    log_fail "PyYAML not found. Please install PyYAML (pip install pyyaml)"
fi
log_pass "PyYAML module available"
echo ""

# Test 2: Validate alerts.yml syntax in main prometheus.yaml
echo "[2/4] Validating alerts.yml in production manifest..."
MAIN_PROM="$REPO_ROOT/manifests/monitoring/prometheus.yaml"

if [[ ! -f "$MAIN_PROM" ]]; then
    log_fail "File not found: $MAIN_PROM"
fi

RESULT=$(python3 << EOF
import yaml
import sys
import re

with open('$MAIN_PROM', 'r') as f:
    content = f.read()

# Extract alerts.yml section
pattern = r'alerts\.yml: \|\n((?:.*\n)*?)(?=^---|\Z)'
match = re.search(pattern, content, re.MULTILINE)

if not match:
    print("ERROR: Could not find alerts.yml section")
    sys.exit(1)

alerts_content = match.group(1)

try:
    parsed = yaml.safe_load(alerts_content)
    groups = parsed.get('groups', [])
    total_rules = sum(len(g.get('rules', [])) for g in groups)
    print(f"OK:{len(groups)}:{total_rules}")
    sys.exit(0)
except yaml.YAMLError as e:
    print(f"ERROR: {e}")
    sys.exit(1)
EOF
)

if [[ $? -eq 0 ]]; then
    IFS=':' read -r status num_groups num_rules <<< "$RESULT"
    log_pass "Production alerts.yml parsed successfully"
    log_info "  Found $num_groups alert groups with $num_rules total rules"
else
    log_fail "Production alerts.yml parsing failed: $RESULT"
fi
echo ""

# Test 3: Validate alerts.yml syntax in staging prometheus.yaml
echo "[3/4] Validating alerts.yml in staging manifest..."
STAGING_PROM="$REPO_ROOT/manifests/staging-debian-bookworm/prometheus.yaml"

if [[ -f "$STAGING_PROM" ]]; then
    RESULT=$(python3 << EOF
import yaml
import sys
import re

with open('$STAGING_PROM', 'r') as f:
    content = f.read()

# Extract alerts.yml section
pattern = r'alerts\.yml: \|\n((?:.*\n)*?)(?=^---|\Z)'
match = re.search(pattern, content, re.MULTILINE)

if not match:
    print("ERROR: Could not find alerts.yml section")
    sys.exit(1)

alerts_content = match.group(1)

try:
    parsed = yaml.safe_load(alerts_content)
    groups = parsed.get('groups', [])
    total_rules = sum(len(g.get('rules', [])) for g in groups)
    print(f"OK:{len(groups)}:{total_rules}")
    sys.exit(0)
except yaml.YAMLError as e:
    print(f"ERROR: {e}")
    sys.exit(1)
EOF
)

    if [[ $? -eq 0 ]]; then
        IFS=':' read -r status num_groups num_rules <<< "$RESULT"
        log_pass "Staging alerts.yml parsed successfully"
        log_info "  Found $num_groups alert groups with $num_rules total rules"
    else
        log_fail "Staging alerts.yml parsing failed: $RESULT"
    fi
else
    log_info "Staging manifest not found, skipping"
fi
echo ""

# Test 4: Check for common YAML pitfalls in alert descriptions
echo "[4/4] Checking for common YAML pitfalls..."
ISSUES_FOUND=0

for PROM_FILE in "$MAIN_PROM" "$STAGING_PROM"; do
    if [[ ! -f "$PROM_FILE" ]]; then
        continue
    fi
    
    BASENAME=$(basename $(dirname "$PROM_FILE"))
    
    # Check for unquoted descriptions with colons after template expressions
    UNQUOTED=$(python3 << EOF
import yaml
import re

with open('$PROM_FILE', 'r') as f:
    content = f.read()

# Extract alerts.yml section
pattern = r'alerts\.yml: \|\n((?:.*\n)*?)(?=^---|\Z)'
match = re.search(pattern, content, re.MULTILINE)

if match:
    alerts_content = match.group(1)
    lines = alerts_content.split('\n')
    
    for i, line in enumerate(lines, 1):
        # Look for description lines that are not quoted but contain {{ }} and colons
        if 'description:' in line:
            # Extract the value part after 'description:'
            parts = line.split('description:', 1)
            if len(parts) == 2:
                value = parts[1].strip()
                # Check if it contains {{ }} and a colon but is not quoted
                if '{{' in value and '}}' in value and ':' in value:
                    if not (value.startswith('"') or value.startswith("'")):
                        print(f"Line {i}: Potentially unquoted description with colon")
EOF
)

    if [[ -n "$UNQUOTED" ]]; then
        log_fail "Found potentially unquoted descriptions in $BASENAME:\n$UNQUOTED"
        ISSUES_FOUND=1
    fi
done

if [[ $ISSUES_FOUND -eq 0 ]]; then
    log_pass "No common YAML pitfalls detected"
fi
echo ""

echo "========================================="
echo "Validation Summary"
echo "========================================="
log_pass "All alerts.yml configurations are valid"
echo ""
echo "Next steps:"
echo "  1. Apply the fixed configuration to your cluster"
echo "  2. Restart the Prometheus pod if it's still failing"
echo "  3. Monitor the pod logs to confirm it starts successfully"
echo ""
