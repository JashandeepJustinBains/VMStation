# VMStation Best Practices & Standards

This document outlines the industry best practices, standards, and design principles applied to the VMStation automation.

## Table of Contents
- [Infrastructure as Code Principles](#infrastructure-as-code-principles)
- [Ansible Best Practices](#ansible-best-practices)
- [Shell Script Standards](#shell-script-standards)
- [Security Best Practices](#security-best-practices)
- [Monitoring & Observability](#monitoring--observability)
- [Error Handling & Logging](#error-handling--logging)
- [Idempotency](#idempotency)
- [Remote-First Architecture](#remote-first-architecture)

## Infrastructure as Code Principles

### 1. Declarative Configuration
All infrastructure is defined declaratively using:
- Kubernetes manifests (YAML)
- Ansible playbooks (YAML)
- Configuration files committed to version control

**Benefits**:
- Version controlled infrastructure
- Reproducible deployments
- Audit trail of changes

### 2. Idempotency
All automation scripts and playbooks are idempotent - safe to run multiple times.

**Implementation**:
```yaml
# Check before action
- name: "Check if cluster is already initialized"
  stat:
    path: /etc/kubernetes/admin.conf
  register: kubeconfig_exists

- name: "Initialize control plane (if not exists)"
  shell: kubeadm init ...
  when: not kubeconfig_exists.stat.exists
```

### 3. Immutable Infrastructure
Where possible, use immutable patterns:
- Container images with pinned versions
- Package versions held at specific versions
- No manual modifications to running systems

## Ansible Best Practices

### 1. Playbook Structure

**Organization**:
```
ansible/
├── playbooks/          # All playbooks
├── inventory/          # Inventory files
├── files/              # Static files
├── templates/          # Jinja2 templates
└── artifacts/          # Generated artifacts
```

**Naming Convention**:
- Use descriptive names: `deploy-cluster.yaml` not `deploy.yaml`
- Use kebab-case: `install-rke2-homelab.yml`
- Use `.yaml` or `.yml` consistently (prefer `.yaml` for playbooks)

### 2. Error Handling

**Always include**:
```yaml
- name: "Critical operation"
  command: some-command
  register: result
  retries: 3
  delay: 5
  until: result.rc == 0
  failed_when: result.rc != 0
```

**For non-critical operations**:
```yaml
- name: "Optional operation"
  command: some-command
  register: result
  failed_when: false
  ignore_errors: true
```

### 3. Logging and Debugging

**Log command output**:
```yaml
- name: "Important operation"
  shell: complex-command
  register: operation_result

- name: "Display operation result"
  debug:
    msg: "{{ operation_result.stdout_lines }}"
```

### 4. Validation and Health Checks

**Always verify after deployment**:
```yaml
- name: "Wait for deployment to be ready"
  shell: kubectl wait --for=condition=available deployment/myapp
  retries: 5
  delay: 10
  until: result.rc == 0
```

### 5. Remote Execution

**All operations via SSH**:
```yaml
# ✅ Good - runs on remote host
- name: "Check service"
  shell: systemctl status kubelet
  
# ❌ Bad - runs on controller
- name: "Check service"
  local_action:
    module: shell
    cmd: systemctl status kubelet
```

## Shell Script Standards

### 1. Strict Error Handling

**Always use**:
```bash
#!/usr/bin/env bash
set -euo pipefail
# -e: Exit on error
# -u: Error on undefined variable
# -o pipefail: Pipe failures cause exit
```

### 2. Logging Functions

**Structured logging**:
```bash
log_timestamp(){ date '+%Y-%m-%d %H:%M:%S'; }
info(){ echo "[$(log_timestamp)] [INFO] $*" >&2; }
warn(){ echo "[$(log_timestamp)] [WARN] $*" >&2; }
err(){ echo "[$(log_timestamp)] [ERROR] $*" >&2; exit 1; }
```

### 3. Input Validation

**Validate all inputs**:
```bash
validate_ip(){
  local ip="$1"
  if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    err "Invalid IP address: $ip"
  fi
}
```

### 4. Dependency Checking

**Check before use**:
```bash
require_bin(){
  command -v "$1" >/dev/null 2>&1 || err "Required binary '$1' not found"
}

require_bin ansible
require_bin kubectl
```

### 5. Retry Logic

**For network operations**:
```bash
retry_cmd(){
  local max_attempts="${1:-3}"
  local delay="${2:-5}"
  shift 2
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    if "$@"; then
      return 0
    fi
    warn "Attempt $attempt/$max_attempts failed"
    sleep "$delay"
    attempt=$((attempt + 1))
  done
  return 1
}
```

## Security Best Practices

### 1. Secret Management

**Never hardcode secrets**:
```yaml
# ❌ Bad
- name: GF_SECURITY_ADMIN_PASSWORD
  value: "admin"

# ✅ Better (for homelab with network isolation)
- name: GF_SECURITY_ADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: grafana-secrets
      key: admin-password
```

**For Ansible**:
```bash
# Use ansible-vault for sensitive data
ansible-vault encrypt group_vars/secrets.yml
```

### 2. Least Privilege

**Service Accounts**:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources: ["nodes", "services", "endpoints", "pods"]
  verbs: ["get", "list", "watch"]
# Only grant what's needed
```

### 3. Network Segmentation

**Homelab Security Model**:
1. Private network (192.168.4.0/24)
2. Firewall at network perimeter
3. NodePort services for internal access
4. Anonymous monitoring (read-only) acceptable for homelab

**For Production**:
- Use Ingress with TLS
- Enable authentication on all services
- Use Network Policies to restrict pod-to-pod communication

### 4. File Permissions

**Sensitive files**:
```bash
# Kubeconfig
chmod 600 /etc/kubernetes/admin.conf
chown root:root /etc/kubernetes/admin.conf

# SSH keys
chmod 600 ~/.ssh/id_rsa
```

## Monitoring & Observability

### 1. Anonymous Access (Homelab)

**Design Decision**:
- Grafana: Anonymous viewer access enabled
- Prometheus: Metrics accessible without auth
- Network-level security (private network)

**Configuration**:
```yaml
env:
- name: GF_AUTH_ANONYMOUS_ENABLED
  value: "true"
- name: GF_AUTH_ANONYMOUS_ORG_ROLE
  value: "Viewer"  # Read-only
```

### 2. Metrics Endpoints

**Expose via NodePort**:
```yaml
spec:
  type: NodePort
  ports:
  - port: 9090
    targetPort: 9090
    nodePort: 30090  # Fixed port for predictability
```

### 3. Health Checks

**Always implement**:
```yaml
livenessProbe:
  httpGet:
    path: /-/healthy
    port: 9090
  initialDelaySeconds: 30
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /-/ready
    port: 9090
  initialDelaySeconds: 5
  periodSeconds: 5
```

### 4. Logging

**Structured logging**:
```bash
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}
```

**Log rotation**:
```yaml
# systemd handles this automatically via journald
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vmstation-autosleep
```

## Error Handling & Logging

### 1. Graceful Degradation

**Handle failures gracefully**:
```yaml
- name: "Optional operation"
  command: non-critical-task
  register: result
  failed_when: false

- name: "Log if failed"
  debug:
    msg: "WARNING: Optional operation failed - continuing"
  when: result.rc != 0
```

### 2. Rollback Strategies

**For critical operations**:
```yaml
- name: "Backup current state"
  copy:
    src: /etc/config.yaml
    dest: /etc/config.yaml.backup
    remote_src: true

- name: "Apply new configuration"
  template:
    src: config.yaml.j2
    dest: /etc/config.yaml
  register: config_update

- name: "Rollback on failure"
  copy:
    src: /etc/config.yaml.backup
    dest: /etc/config.yaml
    remote_src: true
  when: config_update is failed
```

### 3. Log Aggregation

**Centralized logging**:
- systemd journald for system logs
- kubectl logs for container logs
- Log files in `/var/log/` for custom scripts

**Access logs**:
```bash
# System logs
journalctl -u vmstation-autosleep -f

# Kubernetes logs
kubectl logs -n monitoring deployment/prometheus -f

# Custom logs
tail -f /var/log/vmstation-autosleep.log
```

## Idempotency

### 1. Check Before Action

**Pattern**:
```yaml
- name: "Check if resource exists"
  stat:
    path: /path/to/resource
  register: resource_exists

- name: "Create resource if not exists"
  command: create-resource
  when: not resource_exists.stat.exists
```

### 2. Declarative Operations

**Use declarative tools**:
```bash
# ✅ Idempotent
kubectl apply -f manifest.yaml

# ❌ Not idempotent
kubectl create -f manifest.yaml
```

### 3. State Management

**Track state explicitly**:
```bash
# State file
LAST_RUN_FILE="/var/lib/vmstation/last-run"

# Check state
if [[ -f "$LAST_RUN_FILE" ]]; then
  LAST_RUN=$(cat "$LAST_RUN_FILE")
  # Decide if action is needed
fi

# Update state
date +%s > "$LAST_RUN_FILE"
```

## Remote-First Architecture

### 1. SSH-Based Automation

**All operations via SSH**:
```yaml
# Inventory
monitoring_nodes:
  hosts:
    masternode:
      ansible_host: 192.168.4.63
      ansible_user: root
      ansible_ssh_private_key_file: ~/.ssh/id_k3s
```

**Never rely on local state**:
```yaml
# ❌ Bad - assumes running on target
- name: "Local operation"
  local_action:
    module: command
    cmd: systemctl status kubelet

# ✅ Good - explicit SSH
- name: "Remote operation"
  command: systemctl status kubelet
```

### 2. Control Node Setup

**Requirements**:
- Ansible installed
- SSH keys configured
- Network connectivity to all nodes
- No privileged access required on control node

**Verification**:
```bash
# Test SSH connectivity
ansible all -i inventory/hosts.yml -m ping

# Test privilege escalation
ansible all -i inventory/hosts.yml -m shell -a "id" --become
```

### 3. Artifact Collection

**Fetch results to control node**:
```yaml
- name: "Fetch kubeconfig"
  fetch:
    src: /etc/kubernetes/admin.conf
    dest: "{{ playbook_dir }}/../artifacts/kubeconfig"
    flat: true
```

### 4. No Local Dependencies

**Design principle**:
- All tools installed on target nodes
- No assumption about control node OS
- Portable across different control nodes

## Testing & Validation

### 1. Syntax Validation

**Before deployment**:
```bash
# Ansible syntax
ansible-playbook --syntax-check playbook.yaml

# YAML lint
yamllint ansible/

# Shell script lint
shellcheck deploy.sh
```

### 2. Dry-Run Mode

**Test without changes**:
```bash
# Ansible check mode
ansible-playbook playbook.yaml --check

# Custom dry-run flag
./deploy.sh debian --check
```

### 3. Idempotency Testing

**Run twice**:
```bash
# First run - should make changes
./deploy.sh all --yes

# Second run - should be minimal/no changes
./deploy.sh all --yes
```

### 4. Health Checks

**After deployment**:
```bash
# Automated health check
./tests/test-monitoring-access.sh

# Manual verification
kubectl get nodes
kubectl get pods -A
curl http://192.168.4.63:30300
```

## Documentation Standards

### 1. Inline Comments

**When to comment**:
- Complex logic requiring explanation
- Non-obvious design decisions
- Security considerations
- Workarounds for known issues

**When NOT to comment**:
- Self-explanatory code
- What the code does (should be obvious)

### 2. README Files

**Every directory should have**:
- Purpose of the directory
- File organization
- Usage examples
- Common operations

### 3. Operational Documentation

**Include**:
- Deployment procedures
- Troubleshooting guides
- Access instructions
- Recovery procedures

### 4. Change Documentation

**For every PR**:
- What changed
- Why it changed
- How to test
- Rollback procedure (if applicable)

## References

- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html)
- [Kubernetes Production Best Practices](https://kubernetes.io/docs/setup/best-practices/)
- [Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [12-Factor App](https://12factor.net/)
