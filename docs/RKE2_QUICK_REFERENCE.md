# RKE2 Quick Reference Card

## One-Liner Commands

### Deployment
```bash
# Full deployment in one command chain (after cleanup)
cd /srv/monitoring_data/VMStation && \
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/cleanup-homelab.yml && \
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/install-rke2-homelab.yml
```

### Verification
```bash
# Quick health check
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml && \
kubectl get nodes && \
kubectl get pods -A && \
kubectl get pods -n monitoring-rke2
```

### Monitoring Check
```bash
# Test all endpoints
curl -s http://192.168.4.62:9100/metrics | head -5 && \
curl -s http://192.168.4.62:30090/api/v1/status/config | jq -r .status && \
curl -s 'http://192.168.4.62:30090/federate?match[]={job="prometheus"}' | head -5
```

## Common Commands

### Access RKE2 Cluster
```bash
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get nodes
kubectl get pods -A
```

### Check RKE2 Service
```bash
ssh jashandeepjustinbains@192.168.4.62 'sudo systemctl status rke2-server'
ssh jashandeepjustinbains@192.168.4.62 'sudo journalctl -u rke2-server -n 50 --no-pager'
```

### View Logs
```bash
# Installation log
cat /srv/monitoring_data/VMStation/ansible/artifacts/install-rke2-homelab.log

# RKE2 service log
ssh jashandeepjustinbains@192.168.4.62 'sudo journalctl -u rke2-server -f'

# Pod logs
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl logs -n <namespace> <pod-name> -f
```

### Restart RKE2
```bash
ssh jashandeepjustinbains@192.168.4.62 'sudo systemctl restart rke2-server'
```

## File Locations

| Item | Location |
|------|----------|
| **Kubeconfig** | `/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml` |
| **Install Log** | `/srv/monitoring_data/VMStation/ansible/artifacts/install-rke2-homelab.log` |
| **RKE2 Config** | `/etc/rancher/rke2/config.yaml` (on homelab) |
| **RKE2 Role** | `/srv/monitoring_data/VMStation/ansible/roles/rke2/` |
| **Playbooks** | `/srv/monitoring_data/VMStation/ansible/playbooks/` |
| **Cleanup Script** | `/srv/monitoring_data/VMStation/scripts/cleanup-homelab-k8s-artifacts.sh` |

## Endpoints

| Service | URL |
|---------|-----|
| **RKE2 Prometheus** | http://192.168.4.62:30090 |
| **RKE2 Federation** | http://192.168.4.62:30090/federate |
| **RKE2 Node Exporter** | http://192.168.4.62:9100/metrics |
| **Central Prometheus** | http://192.168.4.63:30090 |
| **Grafana** | http://192.168.4.63:30300 |

## Quick Troubleshooting

### Service Won't Start
```bash
ssh jashandeepjustinbains@192.168.4.62 'sudo journalctl -u rke2-server -n 100 --no-pager | tail -50'
```

### Pods Not Running
```bash
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl get pods -A | grep -v Running | grep -v Completed
kubectl describe pod <pod-name> -n <namespace>
```

### Federation Not Working
```bash
# Test endpoint
curl -v http://192.168.4.62:30090/federate

# Check central Prometheus targets
curl -s 'http://192.168.4.63:30090/api/v1/targets' | jq '.data.activeTargets[] | select(.labels.job=="rke2-federation")'
```

### Node Not Ready
```bash
export KUBECONFIG=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml
kubectl describe node homelab | grep -A 10 Conditions
```

## Rollback

### Quick Uninstall
```bash
cd /srv/monitoring_data/VMStation
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/uninstall-rke2-homelab.yml
```

### Manual Uninstall
```bash
ssh jashandeepjustinbains@192.168.4.62 'sudo systemctl stop rke2-server && sudo /usr/local/bin/rke2-uninstall.sh'
```

## Documentation Quick Links

- **Runbook**: `ansible/playbooks/RKE2_DEPLOYMENT_RUNBOOK.md`
- **Deployment Guide**: `docs/RKE2_DEPLOYMENT_GUIDE.md`
- **Federation Guide**: `docs/RKE2_PROMETHEUS_FEDERATION.md`
- **Quick Start**: `docs/RHEL10_DEPLOYMENT_QUICKSTART.md`
- **Role README**: `ansible/roles/rke2/README.md`

## Prometheus Federation Config Snippet

Add to `manifests/monitoring/prometheus.yaml` under `scrape_configs`:

```yaml
- job_name: 'rke2-federation'
  honor_labels: true
  metrics_path: '/federate'
  params:
    'match[]':
      - '{job=~"kubernetes-.*"}'
      - '{job="node-exporter"}'
  static_configs:
    - targets: ['192.168.4.62:30090']
      labels:
        cluster: 'rke2-homelab'
  scrape_interval: 30s
```

Then apply:
```bash
kubectl apply -f manifests/monitoring/prometheus.yaml
kubectl rollout restart -n monitoring deployment/prometheus
```

## Useful Aliases

Add to `~/.bashrc`:
```bash
alias kubectl-rke2='kubectl --kubeconfig=/srv/monitoring_data/VMStation/ansible/artifacts/homelab-rke2-kubeconfig.yaml'
alias rke2-logs='ssh jashandeepjustinbains@192.168.4.62 "sudo journalctl -u rke2-server -f"'
alias rke2-status='ssh jashandeepjustinbains@192.168.4.62 "sudo systemctl status rke2-server"'
```

## Support

- **GitHub Issues**: https://github.com/JashandeepJustinBains/VMStation/issues
- **RKE2 Docs**: https://docs.rke2.io/
- **Prometheus Docs**: https://prometheus.io/docs/

---

**Branch**: `copilot/fix-21930137-7299-4c05-991c-c37074b3f963`  
**Last Updated**: October 2025
