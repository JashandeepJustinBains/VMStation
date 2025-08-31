# Troubleshooting Common Issues

## CrashLoopBackOff Issues
- **Drone CI**: Missing GitHub secrets/configuration → [CrashLoopBackOff Fixes](crashloop_fixes.md#1-drone-ci-crashloopbackoff-fix)
- **Kubernetes Dashboard**: Directory permission errors → [CrashLoopBackOff Fixes](crashloop_fixes.md#2-kubernetes-dashboard-crashloopbackoff-fix)
- **Monitoring Stack**: PV permissions and Loki config → [PV Permissions Guide](../pv_permissions_and_loki_issues.md)

## CI/CD Problems
- Check Drone and registry logs
- Validate kubeconfig secrets
- Use: `./scripts/validate_drone_config.sh`

## Network Issues
- Verify VLAN and switch config
- Check firewall rules

## Cluster Health
- Use `kubectl get nodes` and `kubectl get pods -A`
- Monitor resource usage
- Run: `./scripts/diagnose_monitoring_permissions.sh`

## Permission Issues
- For monitoring: `./scripts/fix_monitoring_permissions.sh`
- For dashboard: `./scripts/fix_k8s_dashboard_permissions.sh`
- General diagnostic: `./scripts/diagnose_monitoring_permissions.sh`
