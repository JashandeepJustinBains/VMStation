# Grafana Datasources

Preconfigured datasources for Grafana.

## Guidelines

- Use FQDNs for in-cluster services, e.g.:
  - `http://prometheus.monitoring.svc.cluster.local:9090`
  - `http://loki.monitoring.svc.cluster.local:3100`
- Do not embed credentials; use Kubernetes Secrets with provisioning.
- Update when service names or namespaces change.
