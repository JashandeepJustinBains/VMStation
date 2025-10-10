# Debian Bookworm Manifests (Staging)

This directory contains Kubernetes manifests for the **Debian Bookworm control-plane** nodes.

## Contents

All manifests in this directory are configured to run on nodes with:
- `node-role.kubernetes.io/control-plane` label
- Node: masternode (192.168.4.63)
- OS: Debian Bookworm

### Manifest Files

| File | Type | Description |
|------|------|-------------|
| grafana-pv.yaml | PersistentVolume | Grafana storage on control-plane |
| grafana.yaml | Deployment + Service | Grafana dashboard with nodeSelector |
| ipmi-exporter.yaml | DaemonSet | IPMI metrics exporter |
| kube-state-metrics.yaml | Deployment | Kubernetes state metrics |
| loki-pv.yaml | PersistentVolume | Loki log storage on control-plane |
| loki.yaml | StatefulSet + Service | Loki log aggregation |
| node-exporter.yaml | DaemonSet | System/hardware metrics (cluster-wide) |
| prometheus-pv.yaml | PersistentVolume | Prometheus storage on control-plane |
| prometheus.yaml | StatefulSet + Service | Prometheus monitoring |
| promtail-pv.yaml | PersistentVolume | Promtail storage on control-plane |

## Validation Status

✅ All manifests have valid YAML syntax
✅ All manifests pass yamllint (except minor style warnings on 2 files)
⚠️ kubectl dry-run requires cluster connection (not available in CI)

## Node Affinity

All PersistentVolumes have explicit nodeAffinity:
```yaml
nodeAffinity:
  required:
    nodeSelectorTerms:
    - matchExpressions:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
```

All Deployments/StatefulSets have nodeSelector:
```yaml
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
```

## Storage Paths

All PVs use `/srv/monitoring_data/` on the control-plane node:
- Prometheus: `/srv/monitoring_data/prometheus` (uid:gid 65534:65534)
- Loki: `/srv/monitoring_data/loki` (uid:gid 10001:10001)
- Grafana: `/srv/monitoring_data/grafana` (uid:gid 472:472)

## Deployment

After operator review and approval:

```bash
# Create final directory
mkdir -p manifests/debian-bookworm

# Move staging to final location
mv manifests/staging-debian-bookworm/* manifests/debian-bookworm/

# Deploy to cluster
for f in manifests/debian-bookworm/*.yaml; do
  kubectl apply -f "$f"
done
```

## Status

**STAGING** - Ready for operator review
- Created: 2025-10-09
- Source: manifests/monitoring/
- Reviewed: ⏳ Pending operator approval
