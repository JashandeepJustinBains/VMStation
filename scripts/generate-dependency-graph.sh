#!/usr/bin/env bash
# Dependency Graph Generator for Kubespray Migration
# Analyzes the canonical workflow and identifies files that are used vs orphaned
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE_DIR="$REPO_ROOT/.cache/migration"
GRAPH_FILE="$CACHE_DIR/kubespray_dependency_graph.json"
ORPHAN_FILE="$CACHE_DIR/orphaned_files.txt"

mkdir -p "$CACHE_DIR"

# Canonical workflow files (as per problem statement)
CANONICAL_WORKFLOW=(
  "deploy.sh"
  "scripts/validate-monitoring-stack.sh"
  "tests/test-sleep-wake-cycle.sh"
  "tests/test-complete-validation.sh"
  "scripts/run-kubespray.sh"
  "scripts/activate-kubespray-env.sh"
  "ansible/playbooks/run-preflight-rhel10.yml"
  "inventory.ini"
)

# Track used files
declare -A USED_FILES
declare -A REASONS

# Mark canonical files as used
for file in "${CANONICAL_WORKFLOW[@]}"; do
  USED_FILES["$file"]=1
  REASONS["$file"]="canonical_workflow"
done

# Function to mark a file as used
mark_used() {
  local file="$1"
  local reason="${2:-dependency}"
  if [[ -f "$REPO_ROOT/$file" ]] && [[ -z "${USED_FILES[$file]:-}" ]]; then
    USED_FILES["$file"]=1
    REASONS["$file"]="$reason"
  fi
}

# Analyze deploy.sh for playbook references
echo "Analyzing deploy.sh..."
while IFS= read -r playbook; do
  mark_used "$playbook" "deploy.sh"
done < <(grep -oE 'ansible/playbooks/[a-zA-Z0-9_-]+\.(yml|yaml)' "$REPO_ROOT/deploy.sh" | sort -u)

# Analyze run-kubespray.sh
echo "Analyzing run-kubespray.sh..."
# run-kubespray.sh uses Kubespray from .cache, mark it as used
USED_FILES["scripts/run-kubespray.sh"]=1

# Analyze activate-kubespray-env.sh
USED_FILES["scripts/activate-kubespray-env.sh"]=1

# Analyze test files
echo "Analyzing test files..."
for test in tests/test-sleep-wake-cycle.sh tests/test-complete-validation.sh; do
  if [[ -f "$REPO_ROOT/$test" ]]; then
    # Find sourced/executed scripts
    while IFS= read -r script; do
      mark_used "$script" "$test"
    done < <(grep -oE '\./[a-zA-Z0-9/_-]+\.sh|tests/[a-zA-Z0-9/_-]+\.sh|scripts/[a-zA-Z0-9/_-]+\.sh' "$REPO_ROOT/$test" | sort -u)
  fi
done

# Analyze playbooks for role and file dependencies
echo "Analyzing playbooks..."
for playbook in $(find "$REPO_ROOT/ansible/playbooks" -name "*.yml" -o -name "*.yaml"); do
  playbook_rel="${playbook#$REPO_ROOT/}"
  if [[ -n "${USED_FILES[$playbook_rel]:-}" ]]; then
    # This playbook is used, find its dependencies
    # Find role references
    while IFS= read -r role; do
      mark_used "ansible/roles/$role/tasks/main.yml" "$playbook_rel"
      mark_used "ansible/roles/$role" "$playbook_rel"
    done < <(grep -oE 'role: [a-zA-Z0-9_-]+' "$playbook" | cut -d' ' -f2 | sort -u)
    
    # Find manifest references
    while IFS= read -r manifest; do
      mark_used "$manifest" "$playbook_rel"
    done < <(grep -oE 'manifests/[a-zA-Z0-9/_.-]+\.(yaml|yml)' "$playbook" | sort -u)
  fi
done

# Analyze monitoring stack playbook specifically
if [[ -f "$REPO_ROOT/ansible/playbooks/deploy-monitoring-stack.yaml" ]]; then
  echo "Analyzing monitoring stack dependencies..."
  mark_used "ansible/playbooks/deploy-monitoring-stack.yaml" "deploy.sh"
  # All monitoring manifests are used
  for manifest in "$REPO_ROOT"/manifests/monitoring/*.yaml; do
    manifest_rel="${manifest#$REPO_ROOT/}"
    mark_used "$manifest_rel" "monitoring_stack"
  done
fi

# Analyze infrastructure services playbook
if [[ -f "$REPO_ROOT/ansible/playbooks/deploy-infrastructure-services.yaml" ]]; then
  mark_used "ansible/playbooks/deploy-infrastructure-services.yaml" "deploy.sh"
  if [[ -d "$REPO_ROOT/manifests/infrastructure" ]]; then
    for manifest in "$REPO_ROOT"/manifests/infrastructure/*.yaml; do
      if [[ -f "$manifest" ]]; then
        manifest_rel="${manifest#$REPO_ROOT/}"
        mark_used "$manifest_rel" "infrastructure_services"
      fi
    done
  fi
fi

# Analyze reset playbook
mark_used "ansible/playbooks/reset-cluster.yaml" "deploy.sh"

# Analyze setup autosleep playbook
mark_used "ansible/playbooks/setup-autosleep.yaml" "deploy.sh"

# Mark inventory files
mark_used "inventory.ini" "canonical"
mark_used "ansible/inventory/hosts.yml" "legacy_but_keep"

# Mark validation script
mark_used "scripts/validate-monitoring-stack.sh" "canonical"

# Mark common test utilities
for test_file in "$REPO_ROOT"/tests/*.sh; do
  test_rel="${test_file#$REPO_ROOT/}"
  if [[ "$test_rel" == *"test-complete-validation.sh"* ]] || \
     [[ "$test_rel" == *"test-sleep-wake-cycle.sh"* ]]; then
    mark_used "$test_rel" "canonical"
  fi
done

# Generate dependency graph JSON
echo "Generating dependency graph..."
cat > "$GRAPH_FILE" <<'EOF'
{
  "canonical_workflow": [
    "deploy.sh reset",
    "deploy.sh setup",
    "deploy.sh debian",
    "deploy.sh monitoring",
    "deploy.sh infrastructure",
    "validate-monitoring-stack.sh",
    "test-sleep-wake-cycle.sh",
    "test-complete-validation.sh"
  ],
  "kubespray_flow": [
    "scripts/run-kubespray.sh",
    "ansible-playbook -i inventory.ini run-preflight-rhel10.yml -l compute_nodes",
    "cd .cache/kubespray && source .venv/bin/activate && ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -b",
    "scripts/activate-kubespray-env.sh",
    "deploy.sh monitoring",
    "deploy.sh infrastructure"
  ],
  "used_files": {
EOF

# Add used files to JSON
first=true
for file in "${!USED_FILES[@]}"; do
  reason="${REASONS[$file]:-unknown}"
  if $first; then
    first=false
  else
    echo "," >> "$GRAPH_FILE"
  fi
  echo -n "    \"$file\": \"$reason\"" >> "$GRAPH_FILE"
done

cat >> "$GRAPH_FILE" <<'EOF'

  },
  "notes": [
    "This graph represents files reachable from the canonical Kubespray workflow",
    "Files not in this graph are candidates for archival or deletion",
    "RKE2 playbooks have been identified as orphaned and should be archived"
  ]
}
EOF

echo "✓ Dependency graph saved to: $GRAPH_FILE"

# Identify orphaned files
echo ""
echo "Identifying orphaned files..."

{
  echo "# Orphaned Files Analysis"
  echo "# Files not reachable from the canonical Kubespray workflow"
  echo "# Generated: $(date)"
  echo ""
  echo "## RKE2-Related Files (to be archived)"
  echo ""
  
  # RKE2 playbooks
  find "$REPO_ROOT/ansible/playbooks" -name "*rke2*" -o -name "*RKE2*" | while read -r file; do
    file_rel="${file#$REPO_ROOT/}"
    if [[ -z "${USED_FILES[$file_rel]:-}" ]]; then
      echo "- $file_rel (reason: RKE2 legacy, Kubespray replaces this)"
    fi
  done
  
  echo ""
  echo "## Potentially Orphaned Scripts"
  echo ""
  
  # Check scripts
  find "$REPO_ROOT/scripts" -name "*.sh" | while read -r file; do
    file_rel="${file#$REPO_ROOT/}"
    if [[ -z "${USED_FILES[$file_rel]:-}" ]] && \
       [[ "$file_rel" != *"run-kubespray.sh"* ]] && \
       [[ "$file_rel" != *"activate-kubespray-env.sh"* ]] && \
       [[ "$file_rel" != *"validate-monitoring-stack.sh"* ]]; then
      echo "- $file_rel (reason: not referenced in canonical workflow)"
    fi
  done
  
  echo ""
  echo "## Potentially Orphaned Tests"
  echo ""
  
  # Check tests
  find "$REPO_ROOT/tests" -name "*.sh" | while read -r file; do
    file_rel="${file#$REPO_ROOT/}"
    if [[ -z "${USED_FILES[$file_rel]:-}" ]] && \
       [[ "$file_rel" != *"test-complete-validation.sh"* ]] && \
       [[ "$file_rel" != *"test-sleep-wake-cycle.sh"* ]]; then
      echo "- $file_rel (reason: not part of canonical test suite)"
    fi
  done
  
  echo ""
  echo "## Notes"
  echo "- RKE2 files should be moved to archive/legacy/"
  echo "- Other orphaned files may be kept for debugging/reference"
  echo "- Files marked as 'legacy_but_keep' in the dependency graph are intentionally kept"
  
} > "$ORPHAN_FILE"

echo "✓ Orphaned files list saved to: $ORPHAN_FILE"

echo ""
echo "Summary:"
echo "  - Used files: ${#USED_FILES[@]}"
echo "  - Dependency graph: $GRAPH_FILE"
echo "  - Orphaned files: $ORPHAN_FILE"
echo ""
echo "Review these files before proceeding with archival."
