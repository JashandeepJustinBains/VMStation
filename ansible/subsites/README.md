VMStation ansible subsites

This directory contains modular sub-playbooks that can be run independently.

How to run:

  ansible-playbook -i ansible/inventory.txt ansible/subsites/01-checks.yaml --check
  ansible-playbook -i ansible/inventory.txt ansible/subsites/03-monitoring.yaml --syntax-check
  ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml --check

Design rules:
- Playbooks must only check permissions and preconditions. They must NOT change ownership or file permissions on remote hosts.
- If a task requires elevated privileges or missing local directories, the playbook prints exact CLI remediation commands for the operator to run.

Available subsites:
- 00-spindown.yaml: **DESTRUCTIVE** - Complete infrastructure cleanup (Podman + Kubernetes removal)
- 01-checks.yaml: Preflight checks (SSH, become access, firewall)
- 02-certs.yaml: Certificate management
- 03-monitoring.yaml: Monitoring stack pre-checks
- 04-jellyfin.yaml: Jellyfin deployment pre-checks
- 05-extra_apps.yaml: Extra applications orchestrator (imports individual app playbooks)
- 06-kubernetes-dashboard.yaml: Kubernetes Dashboard deployment
- 07-drone-ci.yaml: Drone CI deployment  
- 08-mongodb.yaml: MongoDB deployment

**Special Note about 00-spindown.yaml:**
This playbook completely removes Podman and Kubernetes infrastructure and is intentionally
excluded from site.yaml for safety. It requires explicit confirmation to run:

```bash
# Safe dry-run (shows what would be removed):
ansible-playbook -i ansible/inventory.txt ansible/subsites/00-spindown.yaml

# DESTRUCTIVE execution (requires explicit confirmation):
ansible-playbook -i ansible/inventory.txt ansible/subsites/00-spindown.yaml -e confirm_spindown=true
```

The spindown playbook removes:
- All Podman containers, pods, and images
- All Kubernetes clusters, namespaces, and CRDs  
- Container runtime packages (docker, containerd, podman)
- Kubernetes packages (kubeadm, kubelet, kubectl)
- VMStation systemd services
- Registry configurations
- Certificates and TLS configurations
- Helm releases and configuration
- Related configuration files and directories

## Modular Extra Apps Architecture

The extra applications deployment has been refactored into individual, modular playbooks for better maintainability:

### Individual App Playbooks
- `06-kubernetes-dashboard.yaml` - Kubernetes Dashboard only
- `07-drone-ci.yaml` - Drone CI only  
- `08-mongodb.yaml` - MongoDB only

### Orchestrator Playbook
- `05-extra_apps.yaml` - Runs all individual app playbooks in sequence

### Usage Examples

**Deploy all extra apps together (orchestrator):**
```bash
ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml
```

**Deploy individual apps:**
```bash
# Deploy only Kubernetes Dashboard
ansible-playbook -i ansible/inventory.txt ansible/subsites/06-kubernetes-dashboard.yaml

# Deploy only Drone CI (with secret validation)
ansible-playbook -i ansible/inventory.txt ansible/subsites/07-drone-ci.yaml

# Deploy only MongoDB
ansible-playbook -i ansible/inventory.txt ansible/subsites/08-mongodb.yaml
```

**Check what would be deployed (dry run):**
```bash
# Check all apps
ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml --check

# Check individual apps
ansible-playbook -i ansible/inventory.txt ansible/subsites/06-kubernetes-dashboard.yaml --check
ansible-playbook -i ansible/inventory.txt ansible/subsites/07-drone-ci.yaml --check  
ansible-playbook -i ansible/inventory.txt ansible/subsites/08-mongodb.yaml --check
```

**Skip specific apps:**
```bash
# Skip Drone CI (environment variable applies to orchestrator and individual playbook)
SKIP_DRONE=true ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml

# Or deploy other apps individually without Drone
ansible-playbook -i ansible/inventory.txt ansible/subsites/06-kubernetes-dashboard.yaml
ansible-playbook -i ansible/inventory.txt ansible/subsites/08-mongodb.yaml
```

### Benefits of Modular Architecture
1. **Individual deployment** - Deploy only what you need
2. **Better troubleshooting** - Debug apps in isolation  
3. **Easier maintenance** - Update individual apps without affecting others
4. **Flexible deployment** - Skip specific apps easily
5. **Easier expansion** - Add new apps by creating new numbered playbooks

### Adding New Apps
To add a new application (e.g., Redis):
1. Create `ansible/subsites/09-redis.yaml` following existing app structure
2. Add `- import_playbook: 09-redis.yaml` to the orchestrator (`05-extra_apps.yaml`)
3. Test the new app independently before adding to orchestrator
4. Update documentation with the new app details
