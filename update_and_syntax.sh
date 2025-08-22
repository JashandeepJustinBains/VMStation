#!/usr/bin/env bash
set -euo pipefail

# update_and_syntax.sh
# Run this from the repo root: ./update_and_syntax.sh
# - runs ansible-playbook --syntax-check against all playbooks under ansible/plays
# - optionally runs ansible-lint and yamllint if installed
# - uses ansible/inventory.txt if present

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="$SCRIPT_DIR/ansible/inventory.txt"
INVENTORY_ARG=""
if [ -f "$INVENTORY_FILE" ]; then
  INVENTORY_ARG=( -i "$INVENTORY_FILE" )
  echo "Using inventory: $INVENTORY_FILE"
else
  echo "No inventory file at $INVENTORY_FILE, running syntax-check without -i"
fi

# Gather playbook files
mapfile -t PLAYBOOKS < <(find "$SCRIPT_DIR/ansible/plays" -type f -name '*.yaml' -print | sort)
if [ ${#PLAYBOOKS[@]} -eq 0 ]; then
  echo "No playbooks found under $SCRIPT_DIR/ansible/plays"
  exit 1
fi

echo "Found ${#PLAYBOOKS[@]} playbook(s) to syntax-check"
FAILED=0
for pb in "${PLAYBOOKS[@]}"; do
  echo
  echo "=== Syntax-check: $pb ==="
  if ! ansible-playbook "${INVENTORY_ARG[@]}" "$pb" --syntax-check; then
    echo "SYNTAX CHECK FAILED: $pb"
    FAILED=$((FAILED+1))
  else
    echo "OK: $pb"
  fi
done

# Optionally run ansible-lint if available
if command -v ansible-lint >/dev/null 2>&1; then
  echo
  echo "ansible-lint found, running on all playbooks..."
  if ! ansible-lint "${PLAYBOOKS[@]}"; then
    echo "ansible-lint reported issues"
    FAILED=$((FAILED+1))
  else
    echo "ansible-lint OK"
  fi
else
  echo "ansible-lint not found, skipping. Install it to get lint checks."
fi

# Optionally run yamllint if available
if command -v yamllint >/dev/null 2>&1; then
  echo
  echo "yamllint found, running on all playbooks..."
  if ! yamllint "${PLAYBOOKS[@]}"; then
    echo "yamllint reported issues"
    FAILED=$((FAILED+1))
  else
    echo "yamllint OK"
  fi
else
  echo "yamllint not found, skipping. Install it to get YAML style checks."
fi

if [ $FAILED -ne 0 ]; then
  echo
  echo "One or more checks failed (count: $FAILED). Fix issues before deploying."
  exit 2
fi

echo
echo "All syntax checks passed. You can run ./update_and_deploy.sh now."
exit 0
