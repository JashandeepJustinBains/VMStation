# VMStation Home Cloud Infrastructure

VMStation is an Ansible-based home cloud infrastructure project that deploys and manages a monitoring stack (Grafana, Prometheus, Loki) using Podman containers on Debian Linux nodes. The repository automates deployment of monitoring services across multiple nodes using idempotent Ansible playbooks.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Prerequisites and Environment Setup
- Ensure Ansible is installed: `ansible --version` (tested with 2.18.8+)
- Verify Podman collection is available: `ansible-galaxy collection list | grep containers.podman`
- Install podman collection if missing: `ansible-galaxy collection install containers.podman` (may fail in network-restricted environments but usually pre-installed)

### Bootstrap and Configuration
- Create group_vars configuration:
  ```bash
  mkdir -p ansible/group_vars
  cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml 2>/dev/null || echo "Template not found - create ansible/group_vars/all.yml manually"
  ```
- The `ansible/group_vars/all.yml` file MUST exist before running playbooks. Required variables include:
  ```yaml
  monit_root: /srv/monitoring_data
  prometheus_port: 9090
  grafana_port: 3000
  loki_port: 3100
  podman_system_metrics_host_port: 19882
  enable_podman_exporters: true
  enable_grafana: true
  ```

### Build and Validation Commands
- **Syntax validation** (takes ~5 seconds): 
  ```bash
  ./syntax_validator.sh
  ```
  Note: yamllint issues are cosmetic and do not prevent deployment
  
- **Quick syntax check** for single playbook (< 1 second):
  ```bash
  ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml --syntax-check
  ```

- **Check mode validation** - NEVER CANCEL (takes 2-5 minutes):
  ```bash
  ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml --check -vv
  ```
  Set timeout to 10+ minutes when using this command.

### Deployment Commands
- **Full deployment** - NEVER CANCEL (takes 10-30 minutes depending on network):
  ```bash
  ./update_and_deploy.sh
  ```
  OR manually:
  ```bash
  ansible-playbook -i ansible/inventory.txt ansible/plays/site.yaml
  ```
  Set timeout to 45+ minutes for full deployment. Network timeouts are common in sandboxed environments.

- **Monitoring stack only** - NEVER CANCEL (takes 5-15 minutes):
  ```bash
  ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml
  ```
  Set timeout to 30+ minutes.

- **Exporters only** (takes 3-10 minutes):
  ```bash
  ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/install_exporters.yaml
  ```
  Set timeout to 20+ minutes.

### Monitoring Validation
- **Quick monitoring health check** (takes 10-30 seconds):
  ```bash
  ./scripts/validate_monitoring.sh
  ```
  
- **Podman metrics diagnostic** (takes 30-60 seconds):
  ```bash
  ./scripts/podman_metrics_diagnostic.sh
  ```
  
- **Automated podman metrics fix** (takes 2-5 minutes):
  ```bash
  ./scripts/fix_podman_metrics.sh
  ```

## Validation

### Manual Validation Requirements
After deployment, ALWAYS test these specific scenarios to verify the monitoring stack is operational:

1. **Service Availability Test**:
   ```bash
   # Test core monitoring services (replace IPs with your monitoring node)
   curl -s http://192.168.4.63:9090/api/v1/status/config  # Prometheus API
   curl -s http://192.168.4.63:3000/api/health           # Grafana API  
   curl -s http://192.168.4.63:3100/ready                # Loki API
   ```

2. **Metrics Collection Test**:
   ```bash
   # Test node exporters on all nodes
   curl -s http://192.168.4.63:9100/metrics | head -5    # Monitoring node
   curl -s http://192.168.4.61:9100/metrics | head -5    # Storage node  
   curl -s http://192.168.4.62:9100/metrics | head -5    # Compute node
   ```

3. **Container Status Test**:
   ```bash
   # Verify containers are running (run on monitoring node)
   podman ps --filter name=grafana
   podman ps --filter name=prometheus  
   podman ps --filter name=loki
   ```

4. **Dashboard Access Test**:
   - Access Grafana at http://192.168.4.63:3000 (default admin/admin)
   - Verify Prometheus datasource is connected
   - Confirm at least one dashboard displays metrics

### Pre-commit Validation
Always run these commands before committing changes:
```bash
./syntax_validator.sh  # Ignore yamllint style warnings
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml --check
```

## Common Tasks

### Repository Structure
```
├── ansible/
│   ├── deploy.sh                    # Main deployment script
│   ├── inventory.txt               # Node definitions (3 nodes)
│   ├── group_vars/all.yml         # Configuration variables
│   └── plays/
│       ├── site.yaml              # Master playbook
│       ├── monitoring_stack.yaml  # Monitoring deployment
│       └── monitoring/            # Individual monitoring plays
├── scripts/
│   ├── validate_monitoring.sh     # Health check script
│   ├── fix_podman_metrics.sh     # Automated fix script
│   └── podman_metrics_diagnostic.sh # Diagnostic script
├── docs/                          # Documentation
└── syntax_validator.sh           # Ansible syntax checker
```

### Network Configuration  
The inventory defines three nodes:
- **Monitoring Node**: 192.168.4.63 (Grafana, Prometheus, Loki)
- **Storage Node**: 192.168.4.61 (NAS, metrics exporters)  
- **Compute Node**: 192.168.4.62 (Kubernetes, metrics exporters)

### Secrets Management
- NEVER commit plaintext secrets
- Use `ansible-vault` for sensitive data:
  ```bash
  ansible-vault create ansible/group_vars/secrets.yml
  # Add: vault_r430_sudo_password, grafana_admin_pass, quay_username, quay_password
  ```
- Run playbooks with vault: `ansible-playbook ... --ask-vault-pass`

### Troubleshooting Common Issues

**Grafana not starting**: 
1. Check `ansible/group_vars/all.yml` for missing variables
2. Run with verbose logging: `ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml -vv`
3. Check container logs: `podman logs grafana`

**Port 19882 connection refused**:
```bash
./scripts/fix_podman_metrics.sh  # Automated fix
# OR manual fix:
podman rm -f podman_system_metrics 2>/dev/null
podman run --rm --name podman_system_metrics --publish 127.0.0.1:19882:9882 192.168.4.63:5000/podman-system-metrics:latest
```

**Network connectivity issues**: Normal in sandboxed environments. Check-mode deployment will work but actual deployment requires network access to pull container images.

## Critical Timing and Timeout Guidelines

### Timeout Requirements
- **NEVER CANCEL** build or deployment commands
- **Syntax validation**: < 10 seconds timeout
- **Check mode validation**: 10+ minutes timeout  
- **Full deployment**: 45+ minutes timeout
- **Monitoring stack deployment**: 30+ minutes timeout
- **Validation scripts**: 5+ minutes timeout

### Expected Timing
- Syntax check: ~0.4 seconds
- Full syntax validation: ~5 seconds (but may fail on yamllint style issues)
- Check mode: 2-5 minutes (may fail on network connectivity in sandbox)
- Monitoring validation: 10-30 seconds
- Full deployment: 10-30 minutes (network dependent)

### When Commands May Fail
- Network timeouts are NORMAL in sandboxed environments
- Docker image pulls may fail due to connectivity restrictions
- SSH connections to 192.168.4.61/192.168.4.62 will fail in sandbox (expected)
- yamllint style issues are cosmetic and don't prevent deployment

## Additional Resources
- Main documentation: `docs/README.md`
- Monitoring setup: `docs/monitoring/README.md`  
- Existing agent instructions: `.copilot_coding_agent.md` (Windows PowerShell specific)
- Troubleshooting: `docs/monitoring/troubleshooting_podman_metrics.md`