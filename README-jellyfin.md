# Jellyfin Deployment

## Quick Start
1. Copy configuration template: `cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml`
2. Deploy Jellyfin with monitoring stack: `./update_and_deploy.sh`

## Manual Deployment
```bash
ansible-playbook -i ansible/inventory.txt ansible/site.yaml
```

## Configuration
Enable/disable Jellyfin in `ansible/group_vars/all.yml`:
```yaml
jellyfin_enabled: true  # Set to false to disable
jellyfin_node_name: storagenodet3500  # Target node
```

## Validation
Check Jellyfin status:
```bash
kubectl get pods -n jellyfin
kubectl get svc -n jellyfin
curl -I http://192.168.4.61:30096/health
```