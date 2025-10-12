# Rollback Guide

This document describes how to rollback changes if the new Kubespray integration or documentation consolidation causes issues.

## Quick Rollback to Previous State

If you need to revert to the state before this PR:

```bash
# Checkout the previous branch/commit
git checkout main  # or the commit SHA before this PR

# Or merge the previous version
git revert <commit-sha>
```

## Rollback Components

### 1. Revert Kubespray Integration

The Kubespray integration is **additive only** - it doesn't modify existing RKE2 or Debian deployment flows.

**To disable Kubespray**:
- Simply don't run `./scripts/run-kubespray.sh`
- Continue using `./deploy.sh rke2` as before
- The preflight role doesn't conflict with existing deployments

**To remove Kubespray files**:
```bash
rm -rf .cache/kubespray
rm scripts/run-kubespray.sh
rm -rf ansible/roles/preflight-rhel10
rm ansible/playbooks/run-preflight-rhel10.yml
```

### 2. Revert Documentation Changes

Documentation changes are **non-breaking** - old docs are preserved in `docs/archive/`.

**To use old documentation**:
```bash
# Old architecture doc is at:
cat docs/archive/architecture.md

# Old troubleshooting doc is at:
cat docs/archive/troubleshooting.md
```

**To restore old docs to root**:
```bash
cp docs/archive/architecture.md ./
cp docs/archive/troubleshooting.md ./
```

**To remove new docs**:
```bash
rm docs/ARCHITECTURE.md
rm docs/TROUBLESHOOTING.md
rm docs/USAGE.md
rm README.md
```

### 3. Revert TODO.md Changes

The TODO.md changes are **informational only** and don't affect functionality.

**To revert TODO.md**:
```bash
git checkout main -- TODO.md
```

## Validation After Rollback

After any rollback, validate your deployment still works:

```bash
# Test existing deployment commands
./deploy.sh help
./deploy.sh debian --check

# Run validation
./scripts/validate-monitoring-stack.sh
./tests/test-complete-validation.sh
```

## What's Safe to Keep

These additions are **safe and additive**:

1. **preflight-rhel10 role**: Doesn't affect existing deployments
2. **run-kubespray.sh script**: Only stages Kubespray, doesn't deploy anything
3. **New documentation**: Doesn't replace old docs, which are archived
4. **README.md**: New file, doesn't conflict with anything

## What Can Be Safely Removed

If you want to minimize surface area:

1. **Kubespray wrapper** (`scripts/run-kubespray.sh`): Remove if not using Kubespray
2. **Preflight role** (`ansible/roles/preflight-rhel10`): Remove if not using Kubespray
3. **Preflight playbook** (`ansible/playbooks/run-preflight-rhel10.yml`): Remove if not using Kubespray
4. **Consolidated docs**: Revert to archived versions if preferred

## Emergency Rollback Procedure

If deployment is broken after update:

### 1. Check What Changed

```bash
git log --oneline -10
git diff HEAD~3 HEAD
```

### 2. Identify the Issue

```bash
# Check deployment logs
ls -lh ansible/artifacts/

# Check if it's a script issue
bash -n deploy.sh
bash -n scripts/*.sh

# Check if it's a playbook issue
ansible-playbook --syntax-check ansible/playbooks/*.yml
```

### 3. Selective Revert

```bash
# Revert specific file
git checkout HEAD~1 -- path/to/file

# Or revert specific commit
git revert <commit-sha>
```

### 4. Full Revert

```bash
# Revert to known good state
git reset --hard <good-commit-sha>

# Force push if needed (be careful!)
git push --force
```

## Re-Deployment After Rollback

After rollback, re-deploy using standard workflow:

```bash
./deploy.sh reset --yes
./deploy.sh setup
./deploy.sh debian
./deploy.sh monitoring
./deploy.sh infrastructure
```

## Getting Help

If you encounter issues:

1. **Check logs**: `ls -lh ansible/artifacts/*.log`
2. **Run diagnostics**: `./scripts/diagnose-monitoring-stack.sh`
3. **Check troubleshooting**: See docs/TROUBLESHOOTING.md or docs/archive/troubleshooting.md
4. **Create issue**: Open GitHub issue with logs and error messages

## Compatibility Matrix

| Component | Old Deploy | New Deploy | Compatible? |
|-----------|-----------|-----------|-------------|
| deploy.sh | ✅ Works | ✅ Works | ✅ Yes |
| Debian cluster | ✅ Works | ✅ Works | ✅ Yes |
| RKE2 | ✅ Works | ✅ Works | ✅ Yes |
| Monitoring | ✅ Works | ✅ Works | ✅ Yes |
| Tests | ✅ Works | ✅ Works | ✅ Yes |
| Kubespray | ❌ N/A | ✅ New | ✅ Additive |
| Docs | ✅ In root | ✅ In docs/ | ✅ Archived |

## Notes

- **No destructive changes**: All changes are additive or relocations
- **Old workflows preserved**: Existing deployment commands unchanged
- **Backward compatible**: Can use old docs from archive if needed
- **Safe to update**: Low risk of breaking existing deployments

## Prevention

To prevent issues in the future:

1. **Test in dev first**: Always test changes on non-production cluster
2. **Use dry-run**: Test with `--check` flag before actual deployment
3. **Keep backups**: Regular backups of monitoring data
4. **Document changes**: Update TODO.md and CHANGELOG
5. **Version control**: Commit frequently, tag releases

## References

- [ARCHITECTURE.md](ARCHITECTURE.md) - Current architecture
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Troubleshooting guide
- [USAGE.md](USAGE.md) - Usage guide
- Archived docs in `docs/archive/`
