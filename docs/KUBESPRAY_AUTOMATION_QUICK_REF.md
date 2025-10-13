# Kubespray Automation - Quick Reference

## Quick Start

### GitHub Actions (Recommended)
1. Go to **Actions** → **Kubespray Automated Deployment**
2. Click **Run workflow**
3. Wait for completion (~30-60 minutes)
4. Download artifacts for logs and kubeconfig

### Local Execution
```bash
export VMSTATION_SSH_KEY="$(cat ~/.ssh/id_vmstation_ops)"
bash scripts/ops-kubespray-automation.sh
```

## Environment Variables

```bash
export REPO_ROOT="/github/workspace"              # Repository root
export KUBESPRAY_DIR="$REPO_ROOT/.cache/kubespray"  # Kubespray location
export SSH_KEY_PATH="/tmp/id_vmstation_ops"         # SSH key path
```

## Common Commands

### Check Cluster Status
```bash
export KUBECONFIG=/tmp/admin.conf
kubectl get nodes
kubectl get pods -A
```

### Wake Sleeping Nodes
```bash
wakeonlan b8:ac:6f:7e:6c:9d    # storagenodet3500
wakeonlan d0:94:66:30:d6:63    # homelab
```

### Manually Run Components
```bash
# Preflight only
ansible-playbook -i inventory.ini ansible/playbooks/run-preflight-rhel10.yml -l compute_nodes

# Setup Kubespray
bash scripts/run-kubespray.sh

# Deploy cluster (after Kubespray setup)
cd .cache/kubespray
source .venv/bin/activate
ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -b

# Deploy monitoring
./deploy.sh monitoring

# Deploy infrastructure
./deploy.sh infrastructure
```

### View Logs
```bash
# Main log
tail -f ansible/artifacts/run-*/ansible-run-logs/main.log

# Cluster deployment
tail -f ansible/artifacts/run-*/ansible-run-logs/kubespray-cluster.log

# All logs
ls -la ansible/artifacts/run-*/ansible-run-logs/
```

### Check Reports
```bash
# View latest report
cat ansible/artifacts/run-*/ops-report-*.json | jq .

# List all runs
ls -la ansible/artifacts/
```

## Troubleshooting

### Network Unreachable
```bash
# Check connectivity
ping 192.168.4.61
ping 192.168.4.62
ping 192.168.4.63

# View diagnostic bundle
cat ansible/artifacts/run-*/diagnostic-bundle/network-diagnostics.txt

# Manually wake nodes
wakeonlan b8:ac:6f:7e:6c:9d
wakeonlan d0:94:66:30:d6:63
sleep 90

# Test SSH
ssh -i /tmp/id_vmstation_ops root@192.168.4.61 "echo OK"
```

### Preflight Failures
```bash
# View preflight log
cat ansible/artifacts/run-*/ansible-run-logs/preflight.log

# Manual remediation
ansible compute_nodes -i inventory.ini -m shell -a "swapoff -a" --become
ansible compute_nodes -i inventory.ini -m shell -a "modprobe br_netfilter" --become
ansible compute_nodes -i inventory.ini -m package -a "name=python3 state=present" --become
```

### Cluster Deployment Issues
```bash
# View deployment log
tail -100 ansible/artifacts/run-*/ansible-run-logs/kubespray-cluster.log

# Check services on nodes
ansible all -i inventory.ini -m systemd -a "name=containerd state=started" --become
ansible all -i inventory.ini -m systemd -a "name=kubelet state=started" --become

# Restart services
ansible all -i inventory.ini -m systemd -a "name=containerd state=restarted" --become
ansible all -i inventory.ini -m systemd -a "name=kubelet state=restarted" --become
```

### CNI Problems
```bash
# Check CNI pods
kubectl -n kube-system get pods | grep -E "(calico|flannel|weave)"

# Load kernel modules
ansible all -i inventory.ini -m shell -a "modprobe br_netfilter && modprobe overlay" --become

# Restart CNI pods
kubectl -n kube-system delete pods -l k8s-app=kube-proxy
kubectl -n kube-system delete pods -l k8s-app=calico-node  # or your CNI
```

### Node Not Ready
```bash
# Check node status
kubectl get nodes -o wide

# Describe problematic node
kubectl describe node <node-name>

# Check kubelet logs on node
ssh root@<node-ip> "journalctl -u kubelet -n 100 --no-pager"

# Check containerd logs
ssh root@<node-ip> "journalctl -u containerd -n 100 --no-pager"
```

## File Locations

### Configuration
- Main inventory: `inventory.ini`
- YAML inventory: `ansible/inventory/hosts.yml`
- Kubespray inventory: `.cache/kubespray/inventory/mycluster/inventory.ini`

### Scripts
- Main automation: `scripts/ops-kubespray-automation.sh`
- Kubespray setup: `scripts/run-kubespray.sh`
- Deploy wrapper: `deploy.sh`

### Logs & Artifacts
- Logs: `ansible/artifacts/run-<timestamp>/ansible-run-logs/`
- Reports: `ansible/artifacts/run-<timestamp>/ops-report-*.json`
- Diagnostic: `ansible/artifacts/run-<timestamp>/diagnostic-bundle/`
- Backups: `.git/ops-backups/<timestamp>/`

### Kubeconfig
- Runner location: `/tmp/admin.conf`
- Control-plane: `/etc/kubernetes/admin.conf`
- Kubespray artifact: `.cache/kubespray/inventory/mycluster/artifacts/admin.conf`

## Recovery Procedures

### Complete Reset
```bash
# Reset cluster
./deploy.sh reset

# Clean Kubespray cache
rm -rf .cache/kubespray

# Re-run automation
bash scripts/ops-kubespray-automation.sh
```

### Partial Recovery
```bash
# Restart all services
ansible all -i inventory.ini -m systemd -a "name=containerd state=restarted" --become
ansible all -i inventory.ini -m systemd -a "name=kubelet state=restarted" --become

# Re-run just monitoring
./deploy.sh monitoring

# Re-run just infrastructure
./deploy.sh infrastructure
```

### Restore from Backup
```bash
# List backups
ls -la .git/ops-backups/

# View backup
cat .git/ops-backups/<timestamp>/inventory.ini

# Restore file
cp .git/ops-backups/<timestamp>/<file> <destination>
```

## Success Checklist

- [ ] All nodes are Ready: `kubectl get nodes`
- [ ] All system pods Running: `kubectl -n kube-system get pods`
- [ ] Monitoring namespace exists: `kubectl get ns monitoring`
- [ ] Monitoring pods Running: `kubectl -n monitoring get pods`
- [ ] Can create test pod: `kubectl run test --image=nginx`
- [ ] Test pod runs successfully: `kubectl get pods test`
- [ ] Can access services: `kubectl get svc -A`

## Emergency Contacts

- Repository Issues: https://github.com/JashandeepJustinBains/VMStation/issues
- Kubespray Docs: https://kubespray.io/
- Kubernetes Docs: https://kubernetes.io/docs/

## Maintenance

### Regular Tasks
- Check logs weekly for warnings
- Update kubeconfig if regenerated
- Rotate SSH keys monthly
- Review and clean old artifacts
- Update Kubespray version periodically

### Backup Strategy
- Automated backups before each run
- Stored in `.git/ops-backups/`
- Keep last 30 days of backups
- Manual backup before major changes

## Performance Tips

- First run: ~30-60 minutes (includes Kubespray download)
- Subsequent runs: ~15-30 minutes (uses cached Kubespray)
- Monitoring deployment: ~5-10 minutes
- Infrastructure deployment: ~3-5 minutes

## Security Notes

- SSH keys stored in GitHub Secrets only
- Never commit keys to repository
- Kubeconfig excluded from git
- Keys cleaned up after runs
- Rotate keys after testing

## Version Information

- Kubernetes: 1.29
- Kubespray: v2.24.1
- Ansible: 8.5.0
- CNI Plugin: Flannel
- Container Runtime: containerd
