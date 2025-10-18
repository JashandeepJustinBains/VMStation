# Monitoring Manifests

Prometheus, Grafana, Loki, and exporters.

## Components

- `prometheus.yaml` + `prometheus-pv.yaml`
- `grafana.yaml` + `grafana-pv.yaml`
- `loki.yaml` + `loki-pv.yaml`
- `node-exporter.yaml`
- `kube-state-metrics.yaml`
- `ipmi-exporter.yaml`

## Operational Notes

- Directory ownerships must match container UIDs:
  - Prometheus 65534
  - Loki 10001
  - Grafana 472
- Loki WAL recovery can exceed 5 minutes; startupProbe tuned accordingly.
- Use FQDNs in Grafana datasources for headless services.

## Access

- Grafana: `http://<control-plane-ip>:30300`
- Prometheus: `http://<control-plane-ip>:30090`
- Loki: `http://<control-plane-ip>:31100`
