# Tests

Validation and diagnostics scripts for VMStation.

## Running Tests

Run from Linux shell or WSL to ensure compatibility.

- Complete validation suite:
  - `./tests/test-complete-validation.sh`
- Monitoring stack health:
  - `./tests/test-monitoring-exporters-health.sh`
- Loki validation:
  - `./tests/test-loki-validation.sh`
- Sleep/wake cycle:
  - `./tests/test-sleep-wake-cycle.sh`

## Notes

- Some tests require kubectl access to the cluster.
- Outputs are saved to `ansible/artifacts/` where applicable.
