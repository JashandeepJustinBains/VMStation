# VMStation Deployment Tests

This directory contains automated tests for the VMStation deployment system.

## Test Files

### Core Deployment Tests

#### test-modular-deployment.sh

Comprehensive automated tests to verify the new modular deployment commands in deploy.sh.

**What it tests**:
- `./deploy.sh monitoring` uses deploy-monitoring-stack.yaml playbook
- `./deploy.sh infrastructure` uses deploy-infrastructure-services.yaml playbook
- Both commands support --check (dry-run) and --yes flags
- Help documentation includes new commands and recommended workflow
- Playbook files exist and are referenced correctly
- Log file paths are correct
- Existing commands (debian, rke2, all, reset, setup, spindown) remain functional
- Documentation (DEPLOYMENT_RUNBOOK.md, memory.instruction.md) is updated

**How to run**:
```bash
./tests/test-modular-deployment.sh
```

**Expected output**:
```
[TEST-INFO] Testing deploy.sh modular deployment commands
[TEST-PASS] ✓ monitoring command uses deploy-monitoring-stack.yaml
[TEST-PASS] ✓ infrastructure command uses deploy-infrastructure-services.yaml
[TEST-PASS] ✓ monitoring command supports --yes flag
[TEST-PASS] ✓ infrastructure command supports --yes flag
[TEST-PASS] ✓ help includes monitoring command
[TEST-PASS] ✓ help includes infrastructure command
...
[TEST-INFO] ALL TESTS PASSED (13/13)
```

#### test-deploy-limits.sh

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

### Auto-Sleep/Wake Tests

#### test-autosleep-wake-validation.sh

Validates auto-sleep and wake configuration on both storagenodet3500 (Debian) and homelab (RHEL10).

**What it tests**:
- Systemd timer configuration on both nodes
- Auto-sleep scripts existence and permissions
- Wake-on-LAN script and service
- kubectl access from control plane
- WoL tool availability
- Node reachability
- Monitoring services configuration
- Log files and directories
- Systemd timer schedules

**How to run**:
```bash
./tests/test-autosleep-wake-validation.sh
```

#### test-sleep-wake-cycle.sh

⚠️ **DESTRUCTIVE TEST** - Automated sleep/wake cycle validation.

**What it tests**:
- Records initial cluster state
- Triggers cluster sleep (cordons/drains nodes)
- Sends Wake-on-LAN packets
- Measures wake time
- Validates service restoration (kubelet, rke2, node-exporter)
- Validates monitoring stack after wake

**How to run**:
```bash
./tests/test-sleep-wake-cycle.sh
```

**Note**: This test requires user confirmation and will temporarily disrupt the cluster.

### Monitoring & Exporter Tests

#### test-monitoring-exporters-health.sh

Validates monitoring exporters and dashboard health.

**What it tests**:
- Prometheus targets health (up/down status)
- Node exporter health on all nodes
- IPMI exporter health and credentials
- Dashboard metric validation (non-zero values)
- Grafana dashboards availability
- Loki log aggregation health
- Service connectivity with concise curl output

**How to run**:
```bash
./tests/test-monitoring-exporters-health.sh
```

#### test-loki-validation.sh

Validates Loki log aggregation and connectivity.

**What it tests**:
- Loki pod status
- Loki service configuration and endpoints
- Loki API connectivity
- Promtail (log shipper) status
- Loki DNS resolution
- Loki datasource in Grafana

**How to run**:
```bash
./tests/test-loki-validation.sh
```

#### test-headless-service-endpoints.sh

Diagnoses and validates headless service endpoints for Prometheus and Loki.

**What it tests**:
- Service selector and pod label matching
- Pod status (Running, Ready, CrashLoopBackOff)
- StatefulSet replica status
- Endpoint population for headless services
- PVC/PV binding and status
- DNS resolution for headless service FQDNs
- Common root causes: empty endpoints, label mismatch, permission errors
- Provides fix recommendations based on detected issues

**How to run**:
```bash
./tests/test-headless-service-endpoints.sh
```

**Expected output**:
```
[1/10] Checking monitoring namespace...
✓ Monitoring namespace exists

[2/10] Checking pod status in monitoring namespace...
✓ Found 1 Prometheus pod(s)
✓ Prometheus pod(s) are Ready
✓ Found 1 Loki pod(s)
✓ Loki pod(s) are Ready

[6/10] Checking service endpoints...
✓ Prometheus endpoints: 10.244.0.123:9090
✓ Loki endpoints: 10.244.0.124:3100
...
```

**Related documentation**:
- `docs/HEADLESS_SERVICE_ENDPOINTS_TROUBLESHOOTING.md` - Full troubleshooting guide
- `docs/HEADLESS_SERVICE_ENDPOINTS_QUICK_REFERENCE.md` - Quick command reference

#### test-monitoring-access.sh (Updated)

Validates monitoring endpoints with concise curl output.

**What it tests**:
- Grafana web UI and API access
- Prometheus web UI and health
- Node exporter metrics
- Grafana datasources
- Grafana dashboards
- Prometheus metrics collection
- Anonymous access configuration

**How to run**:
```bash
./tests/test-monitoring-access.sh
```

**Output format**: Now includes concise curl status messages:
```
curl http://192.168.4.63:30090/-/healthy ok
curl http://192.168.4.63:30300/api/health ok
```

### Complete Validation Suite

#### test-complete-validation.sh

Master test suite that runs all validation tests in sequence.

**What it tests**:
- Phase 1: Auto-sleep/wake configuration
- Phase 2: Monitoring health (exporters, Loki, access)
- Phase 3: Sleep/wake cycle (optional, requires confirmation)

**How to run**:
```bash
./tests/test-complete-validation.sh
```

**Features**:
- Color-coded output
- Suite-level pass/fail tracking
- Optional destructive tests with user confirmation
- Comprehensive summary report

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
