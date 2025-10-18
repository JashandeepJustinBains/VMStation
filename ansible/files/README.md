# Files and Templates

Support artifacts for deployments.

- Grafana dashboards: `grafana_dashboards/`
- Grafana datasources: `grafana_datasources/`
- Misc Kubernetes manifests placed by playbooks

## Notes

- Update dashboards and datasources to reference services via FQDN (e.g., `prometheus.monitoring.svc.cluster.local:9090`).
- Avoid embedding credentials; use Kubernetes Secrets where necessary.
