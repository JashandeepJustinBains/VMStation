#!/usr/bin/env bash
# Security Audit Script for VMStation
# Validates security configurations and best practices
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "VMStation Security Audit"
echo "========================================="
echo ""

WARNINGS=0
ERRORS=0
PASSED=0

# Audit function
audit_item() {
  local severity="$1"  # INFO, WARN, ERROR
  local name="$2"
  local status="$3"  # PASS, FAIL
  local message="$4"
  
  case "$status" in
    PASS)
      echo -e "${GREEN}✅ PASS${NC}: $name"
      PASSED=$((PASSED + 1))
      ;;
    FAIL)
      case "$severity" in
        ERROR)
          echo -e "${RED}❌ ERROR${NC}: $name - $message"
          ERRORS=$((ERRORS + 1))
          ;;
        WARN)
          echo -e "${YELLOW}⚠️  WARNING${NC}: $name - $message"
          WARNINGS=$((WARNINGS + 1))
          ;;
        INFO)
          echo -e "ℹ️  INFO: $name - $message"
          ;;
      esac
      ;;
  esac
}

# 1. Check for hardcoded secrets in code
echo "[1/10] Checking for hardcoded secrets..."
if grep -r "password.*=.*['\"]" ansible/playbooks/ manifests/ --include="*.yaml" --include="*.yml" 2>/dev/null | grep -v "admin.conf" | grep -v "# Change in production" | grep -q .; then
  audit_item "WARN" "Hardcoded passwords" "FAIL" "Found potential hardcoded passwords"
  echo "  Review these files and use Kubernetes Secrets or ansible-vault"
else
  audit_item "INFO" "Hardcoded passwords" "PASS" ""
fi

echo ""

# 2. Check SSH key permissions
echo "[2/10] Checking SSH key security..."
if [[ -d ~/.ssh ]]; then
  ssh_dir_perms=$(stat -c '%a' ~/.ssh 2>/dev/null || stat -f '%A' ~/.ssh 2>/dev/null || echo "unknown")
  if [[ "$ssh_dir_perms" == "700" ]]; then
    audit_item "INFO" "SSH directory permissions" "PASS" ""
  else
    audit_item "WARN" "SSH directory permissions" "FAIL" "~/.ssh should be 700, found $ssh_dir_perms"
  fi
  
  # Check private key permissions
  if ls ~/.ssh/id_* ~/.ssh/id_*.pem >/dev/null 2>&1; then
    for key in ~/.ssh/id_* ~/.ssh/id_*.pem; do
      if [[ -f "$key" ]] && [[ "$key" != *.pub ]]; then
        key_perms=$(stat -c '%a' "$key" 2>/dev/null || stat -f '%A' "$key" 2>/dev/null || echo "unknown")
        if [[ "$key_perms" == "600" ]]; then
          audit_item "INFO" "SSH key permissions ($key)" "PASS" ""
        else
          audit_item "WARN" "SSH key permissions ($key)" "FAIL" "Should be 600, found $key_perms"
        fi
      fi
    done
  fi
else
  audit_item "INFO" "SSH directory" "PASS" "Not applicable (no ~/.ssh directory)"
fi

echo ""

# 3. Check for ansible-vault encrypted files
echo "[3/10] Checking for encrypted sensitive files..."
if [[ -f ansible/inventory/group_vars/secrets.yml ]]; then
  if grep -q "ANSIBLE_VAULT" ansible/inventory/group_vars/secrets.yml; then
    audit_item "INFO" "Ansible vault encryption" "PASS" ""
  else
    audit_item "WARN" "Ansible vault encryption" "FAIL" "secrets.yml not encrypted with ansible-vault"
  fi
else
  audit_item "INFO" "Secrets file" "PASS" "No secrets.yml found (acceptable for homelab)"
fi

echo ""

# 4. Check Kubernetes manifest security
echo "[4/10] Checking Kubernetes security configurations..."

# Check for privileged containers
if grep -r "privileged: true" manifests/ --include="*.yaml" 2>/dev/null | grep -q .; then
  audit_item "WARN" "Privileged containers" "FAIL" "Found privileged container configurations"
  echo "  Consider using specific capabilities instead"
else
  audit_item "INFO" "Privileged containers" "PASS" ""
fi

# Check for host network usage
if grep -r "hostNetwork: true" manifests/ --include="*.yaml" 2>/dev/null | grep -q .; then
  audit_item "WARN" "Host network usage" "FAIL" "Pods using host network detected"
  echo "  Review necessity of hostNetwork configuration"
else
  audit_item "INFO" "Host network usage" "PASS" ""
fi

# Check for resource limits
if grep -r "kind: Deployment" manifests/ --include="*.yaml" -A 50 2>/dev/null | grep -q "resources:"; then
  audit_item "INFO" "Resource limits" "PASS" "Resource limits are defined"
else
  audit_item "WARN" "Resource limits" "FAIL" "Some deployments may be missing resource limits"
fi

echo ""

# 5. Check for RBAC configurations
echo "[5/10] Checking RBAC configurations..."
if grep -r "kind: ClusterRole" manifests/ ansible/ --include="*.yaml" 2>/dev/null | grep -q .; then
  audit_item "INFO" "RBAC ClusterRoles" "PASS" "ClusterRoles are defined"
  
  # Check for overly permissive rules
  if grep -r "verbs:.*\*" manifests/ ansible/ --include="*.yaml" 2>/dev/null | grep -q .; then
    audit_item "WARN" "RBAC wildcard verbs" "FAIL" "Found wildcard verbs in RBAC rules"
    echo "  Consider using specific verbs instead of '*'"
  else
    audit_item "INFO" "RBAC verb specificity" "PASS" ""
  fi
else
  audit_item "INFO" "RBAC" "PASS" "No ClusterRoles found (acceptable for basic setup)"
fi

echo ""

# 6. Check file permissions on scripts
echo "[6/10] Checking script file permissions..."
script_issues=0
if ls deploy.sh tests/*.sh scripts/*.sh >/dev/null 2>&1; then
  for script in deploy.sh tests/*.sh scripts/*.sh; do
    if [[ -f "$script" ]]; then
      perms=$(stat -c '%a' "$script" 2>/dev/null || stat -f '%A' "$script" 2>/dev/null || echo "unknown")
      if [[ "$perms" == "755" ]] || [[ "$perms" == "750" ]]; then
        # Good
        :
      elif [[ "$perms" == "777" ]]; then
        audit_item "WARN" "Script permissions ($script)" "FAIL" "World-writable script detected (777)"
        script_issues=$((script_issues + 1))
      fi
    fi
  done
fi

if [[ $script_issues -eq 0 ]]; then
  audit_item "INFO" "Script permissions" "PASS" ""
fi

echo ""

# 7. Check for .gitignore security
echo "[7/10] Checking .gitignore for sensitive patterns..."
if [[ -f .gitignore ]]; then
  patterns=("*.key" "*.pem" "*.vault" "kubeconfig" "secrets.yml")
  missing_patterns=()
  
  for pattern in "${patterns[@]}"; do
    if ! grep -q "$pattern" .gitignore; then
      missing_patterns+=("$pattern")
    fi
  done
  
  if [[ ${#missing_patterns[@]} -eq 0 ]]; then
    audit_item "INFO" "Gitignore coverage" "PASS" ""
  else
    audit_item "WARN" "Gitignore coverage" "FAIL" "Missing patterns: ${missing_patterns[*]}"
  fi
else
  audit_item "ERROR" "Gitignore file" "FAIL" "No .gitignore found"
fi

echo ""

# 8. Check monitoring security (homelab context)
echo "[8/10] Checking monitoring security configuration..."
if grep -r "GF_AUTH_ANONYMOUS_ENABLED" manifests/ --include="*.yaml" 2>/dev/null | grep -q "true"; then
  audit_item "INFO" "Grafana anonymous access" "PASS" "Enabled (acceptable for homelab with network isolation)"
  echo "  For production: Disable anonymous access and enable authentication"
else
  audit_item "INFO" "Grafana anonymous access" "PASS" "Not configured or disabled"
fi

if grep -r "GF_AUTH_ANONYMOUS_ORG_ROLE" manifests/ --include="*.yaml" 2>/dev/null | grep -q "Viewer"; then
  audit_item "INFO" "Grafana anonymous role" "PASS" "Limited to Viewer (read-only)"
else
  audit_item "INFO" "Grafana anonymous role" "PASS" "Not applicable"
fi

echo ""

# 9. Check for secure network configuration
echo "[9/10] Checking network security..."

# Check for NodePort services
if grep -r "type: NodePort" manifests/ --include="*.yaml" 2>/dev/null | grep -q .; then
  audit_item "INFO" "NodePort services" "PASS" "Used (acceptable for homelab)"
  echo "  For production: Consider using Ingress with TLS"
else
  audit_item "INFO" "NodePort services" "PASS" "Not used"
fi

# Check for LoadBalancer services
if grep -r "type: LoadBalancer" manifests/ --include="*.yaml" 2>/dev/null | grep -q .; then
  audit_item "INFO" "LoadBalancer services" "PASS" "Used"
else
  audit_item "INFO" "LoadBalancer services" "PASS" "Not used"
fi

echo ""

# 10. Check for container image security
echo "[10/10] Checking container image configurations..."

# Check for latest tag usage
if grep -r "image:.*:latest" manifests/ ansible/ --include="*.yaml" 2>/dev/null | grep -q .; then
  audit_item "WARN" "Container image tags" "FAIL" "Using :latest tag detected"
  echo "  Pin to specific versions for reproducibility"
else
  audit_item "INFO" "Container image tags" "PASS" "Specific versions used"
fi

# Check for official images
if grep -r "image:" manifests/ ansible/ --include="*.yaml" 2>/dev/null | grep -v "# " | grep -q .; then
  audit_item "INFO" "Container images" "PASS" "Images specified"
  echo "  Verify these are from trusted sources:"
  grep -r "image:" manifests/ ansible/ --include="*.yaml" 2>/dev/null | grep -v "# " | sed 's/.*image: */  - /' | sort -u
else
  audit_item "INFO" "Container images" "PASS" "No images found"
fi

echo ""

# Summary
echo "========================================="
echo "Security Audit Summary"
echo "========================================="
echo -e "${GREEN}Passed:${NC}   $PASSED"
echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
echo -e "${RED}Errors:${NC}   $ERRORS"
echo ""

if [[ $ERRORS -gt 0 ]]; then
  echo "❌ Security audit found critical issues that should be addressed"
  exit 1
elif [[ $WARNINGS -gt 0 ]]; then
  echo "⚠️  Security audit found warnings - review recommended"
  exit 0
else
  echo "✅ Security audit passed with no critical issues"
  exit 0
fi
