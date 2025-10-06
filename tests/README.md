# VMStation Deployment Tests

This directory contains automated tests for the VMStation deployment system.

## Test Files

### test-deploy-limits.sh

Automated tests to verify that the deploy.sh script correctly limits deployments to the appropriate hosts.

**What it tests**:
- `./deploy.sh debian` uses `--limit monitoring_nodes,storage_nodes`
- `./deploy.sh debian` does NOT target homelab (compute_nodes)
- `./deploy.sh rke2` uses the install-rke2-homelab.yml playbook
- `./deploy.sh reset` handles both Debian and RKE2 cleanup
- `./deploy.sh all` includes both deployment phases

**How to run**:
```bash
./tests/test-deploy-limits.sh
```

**Expected output**:
```
[TEST-INFO] Testing deploy.sh --limit behavior
[TEST-PASS] ✓ debian command includes monitoring_nodes,storage_nodes
[TEST-PASS] ✓ debian command does not target homelab (compute_nodes)
[TEST-PASS] ✓ rke2 command uses install-rke2-homelab.yml playbook
[TEST-PASS] ✓ reset command includes both Debian and RKE2 playbooks
[TEST-PASS] ✓ all command includes both phases
[TEST-INFO] ALL TESTS PASSED
```

## Running All Tests

```bash
# Run automated tests
./tests/test-deploy-limits.sh

# Run manual dry-run tests (see DEPLOYMENT_TEST_PLAN.md)
./deploy.sh debian --check
./deploy.sh rke2 --check --yes
./deploy.sh reset --check --yes
./deploy.sh all --check --with-rke2
```

## Test Documentation

See [DEPLOYMENT_TEST_PLAN.md](../docs/DEPLOYMENT_TEST_PLAN.md) for:
- Complete test plan
- Manual test procedures
- Integration tests (requires live cluster)
- Acceptance criteria
- Troubleshooting guide

## CI/CD Integration

These tests are suitable for CI/CD pipelines:

```yaml
test:
  script:
    - ./tests/test-deploy-limits.sh
    - ./deploy.sh debian --check
    - ./deploy.sh rke2 --check --yes
    - ./deploy.sh all --check --with-rke2
```

## Adding New Tests

When adding new deploy.sh commands or flags:

1. Add test case to `test-deploy-limits.sh`
2. Update this README
3. Update `DEPLOYMENT_TEST_PLAN.md`
4. Run tests to verify

## Test Results

All tests currently passing: ✅

Last tested: See git commit history
