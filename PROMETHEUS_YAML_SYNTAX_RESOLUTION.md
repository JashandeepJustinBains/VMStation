# Prometheus YAML Syntax Error - Resolution Summary

## Problem
Prometheus pod `prometheus-0` was stuck in `CrashLoopBackOff` state with the following error:
```
level=error component="rule manager" msg="loading groups failed" 
err="/etc/prometheus/rules/alerts.yml: yaml: line 95: mapping values are not allowed in this context"
```

## Root Cause
The error was caused by an unquoted colon in a YAML string value on line 95 of the `alerts.yml` configuration embedded in the `prometheus-rules` ConfigMap.

**Problematic line (line 95):**
```yaml
description: Syslog server receiving {{ $value }} messages/sec (threshold: 1000/sec).
```

**Why it failed:**
In YAML, a colon followed by a space (`: `) is interpreted as a key-value separator. The string `(threshold: 1000/sec)` contained an unquoted colon, which YAML parsers interpreted as attempting to define a nested mapping within a string value, causing a syntax error.

## Solution
The fix was simple: Quote the description string to treat it as a literal string value.

**Fixed line:**
```yaml
description: "Syslog server receiving {{ $value }} messages/sec (threshold: 1000/sec)."
```

## Files Changed
1. **`manifests/monitoring/prometheus.yaml`** (line 436)
   - Fixed the unquoted description in the `HighSyslogMessageRate` alert rule

2. **`manifests/staging-debian-bookworm/prometheus.yaml`** (line 436)
   - Applied the same fix to the staging environment manifest

3. **`tests/test-prometheus-alerts-syntax.sh`** (new file)
   - Created a dedicated test script to validate Prometheus alerts YAML syntax
   - Tests both production and staging manifests
   - Checks for common YAML pitfalls in alert descriptions

4. **`scripts/fix-prometheus-yaml-syntax.sh`** (new file)
   - Created an automated remediation script for operators
   - Validates, applies, and restarts Prometheus with proper error handling

5. **`docs/TROUBLESHOOTING_GUIDE.md`**
   - Added section on diagnosing YAML syntax errors in alert rules
   - Included common patterns and fixes

## Verification

All changes have been validated:

✅ **YAML Syntax Validation**
- Both production and staging manifests parse successfully
- All 14 YAML documents in each file are valid
- 5 alert groups with 13 total rules validated

✅ **Test Coverage**
- New test script validates alerts.yml syntax
- Existing monitoring config validation tests pass
- No YAML pitfalls detected

✅ **Alert Rules Integrity**
- All alert groups preserved:
  - `node-health.rules`: 3 rules
  - `dns-network.rules`: 2 rules
  - `time-sync.rules`: 3 rules
  - `logging.rules`: 2 rules (including the fixed HighSyslogMessageRate)
  - `monitoring.rules`: 3 rules

## Deployment Instructions

### Option 1: Automated (Recommended)
Run the provided remediation script:
```bash
./scripts/fix-prometheus-yaml-syntax.sh
```

This script will:
1. Validate the YAML syntax
2. Apply the corrected configuration
3. Restart the Prometheus pod
4. Wait for the pod to become ready
5. Verify no errors in logs

### Option 2: Manual
```bash
# Apply the updated ConfigMap
kubectl apply -f manifests/monitoring/prometheus.yaml

# Restart the Prometheus pod
kubectl delete pod prometheus-0 -n monitoring

# Monitor the pod startup
kubectl get pods -n monitoring -w

# Check logs for successful startup
kubectl logs -n monitoring prometheus-0 -f
```

## Expected Outcome

After applying the fix:

1. **Prometheus pod starts successfully**
   - No more "mapping values are not allowed" errors
   - Alert rules load without errors
   - Pod transitions from Init → Running → Ready (1/2 → 2/2)

2. **Startup probe passes**
   - HTTP probe to `/-/ready` returns 200 instead of 503
   - Container becomes ready within 30-60 seconds

3. **Service endpoints populated**
   - The headless `prometheus` service gets endpoints
   - Other services (Grafana, Alertmanager) can connect to Prometheus

4. **Alert rules active**
   - All 13 alert rules are loaded and active
   - Alerts can be viewed at `http://<prometheus>:9090/alerts`

## Prevention

To prevent similar issues in the future:

1. **Always quote YAML strings containing special characters**
   - Especially when strings contain colons followed by spaces
   - Template expressions like `{{ $value }}` followed by colons

2. **Run validation tests before deployment**
   ```bash
   ./tests/test-prometheus-alerts-syntax.sh
   ```

3. **Use `promtool` to validate configurations**
   ```bash
   kubectl exec -n monitoring prometheus-0 -- \
     promtool check config /etc/prometheus/prometheus.yml
   ```

4. **Review YAML syntax in PRs**
   - The new test script can be integrated into CI/CD pipelines
   - Check for unquoted strings with special characters

## References

- Problem statement: `Output_for_Copilot.txt` lines 2853-2854
- Prometheus logs showed YAML parse error at line 95
- YAML specification: Colons in unquoted strings require special handling
- Kubernetes ConfigMap propagation delay: ~60 seconds after update

## Related Issues

This fix addresses the immediate blocking issue. Other observations from the diagnostic output:

- ✅ **Permissions are correct**: hostPath owned by 65534:65534 (nobody:nogroup)
- ✅ **Init container successful**: `init-chown-data` completed correctly  
- ✅ **PV/PVC bound correctly**: `prometheus-storage-prometheus-0` → `prometheus-pv`
- ⚠️  **TSDB corruption**: Was detected but auto-repaired (separate issue, not blocking)

The YAML syntax error was the **primary blocker** preventing Prometheus from starting. Once this is fixed, Prometheus should start normally.

---

**Status**: ✅ Fixed and validated  
**Impact**: High - Unblocks Prometheus pod startup  
**Risk**: Low - Single-line change, well-tested  
**Rollback**: Revert ConfigMap to previous version if needed
