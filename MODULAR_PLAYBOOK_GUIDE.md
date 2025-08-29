# VMStation Modular Playbook Architecture Guide

## Overview

VMStation uses a modular playbook architecture that allows operators to run focused deployment checks and operations. All playbooks follow non-destructive principles, providing CLI remediation commands instead of making automated system changes.

## Architecture Components

### 1. Main Site Orchestrator
- **File**: `ansible/site.yaml`
- **Purpose**: Imports all subsites in recommended order for complete deployment
- **Usage**: `ansible-playbook -i ansible/inventory.txt ansible/site.yaml`

### 2. Modular Subsites
Located in `ansible/subsites/`, these focused playbooks handle specific aspects:

#### 01-checks.yaml - Preflight Checks
**Purpose**: Verify SSH connectivity, become/root access, firewall configuration, and port accessibility.

```bash
# Run preflight checks
ansible-playbook -i ansible/inventory.txt ansible/subsites/01-checks.yaml

# Check syntax first
ansible-playbook -i ansible/inventory.txt ansible/subsites/01-checks.yaml --syntax-check

# Dry run mode
ansible-playbook -i ansible/inventory.txt ansible/subsites/01-checks.yaml --check
```

**What it checks**:
- SSH connectivity to all hosts
- Ansible become (sudo/root) access
- Firewall rules and required port accessibility (SSH, Kubernetes API, monitoring ports)
- SELinux status and recommendations

**Safe behavior**: Only performs read-only checks. Provides exact CLI commands for any missing configuration.

#### 02-certs.yaml - Certificate Management
**Purpose**: Generate TLS certificates locally and provide distribution instructions.

```bash
# Generate certificates (local only)
ansible-playbook -i ansible/inventory.txt ansible/subsites/02-certs.yaml

# Check what would be generated
ansible-playbook -i ansible/inventory.txt ansible/subsites/02-certs.yaml --check
```

**What it does**:
- Creates local certificate directory (`./ansible/certs/`)
- Generates CA certificate and private key
- Creates cert-manager ClusterIssuer and Certificate templates
- Provides manual distribution commands via scp/ssh

**Safe behavior**: Only creates local files. Never copies files to remote hosts or changes permissions. Provides exact scp/ssh commands for manual distribution.

#### 03-monitoring.yaml - Monitoring Stack
**Purpose**: Pre-check monitoring requirements and provide deployment instructions.

```bash
# Check monitoring prerequisites
ansible-playbook -i ansible/inventory.txt ansible/subsites/03-monitoring.yaml

# Verify syntax
ansible-playbook -i ansible/inventory.txt ansible/subsites/03-monitoring.yaml --syntax-check
```

**What it checks**:
- Kubernetes connectivity (kubectl availability)
- Monitoring namespace existence
- Prometheus Operator CRDs (ServiceMonitor, etc.)
- Monitoring data directories and permissions
- Node exporter availability
- SELinux contexts for container directories

**Safe behavior**: Only performs checks and reports. Provides Helm installation commands and precise directory creation steps with recommended permissions.

#### 04-jellyfin.yaml - Jellyfin Pre-checks
**Purpose**: Validate Jellyfin deployment requirements and storage configuration.

```bash
# Check Jellyfin prerequisites
ansible-playbook -i ansible/inventory.txt ansible/subsites/04-jellyfin.yaml

# Verify syntax
ansible-playbook -i ansible/inventory.txt ansible/subsites/04-jellyfin.yaml --syntax-check
```

**What it checks**:
- kubectl availability
- Jellyfin namespace existence
- ServiceMonitor CRD availability for monitoring integration
- Storage node configuration and labeling
- Required directories on storage node (/mnt/jellyfin-config, /srv/media)

**Safe behavior**: Only checks and provides CLI commands. Never modifies storage or creates directories automatically.

## Host Inventory Context

The playbooks work with this host structure:
- **masternode** (192.168.4.63): Debian-based controller where operators SSH and run playbooks locally
- **storagenodet3500** (192.168.4.61): Debian-based storage node where Jellyfin is scheduled  
- **r430computenode** (192.168.4.62): RHEL 10 compute node for workloads

## Running Selected Playbooks

### Method 1: Individual Execution (Recommended)

```bash
# 1. First, run preflight checks
ansible-playbook -i ansible/inventory.txt ansible/subsites/01-checks.yaml

# 2. Generate certificates if TLS is enabled
ansible-playbook -i ansible/inventory.txt ansible/subsites/02-certs.yaml

# 3. Check monitoring prerequisites
ansible-playbook -i ansible/inventory.txt ansible/subsites/03-monitoring.yaml

# 4. Check Jellyfin prerequisites
ansible-playbook -i ansible/inventory.txt ansible/subsites/04-jellyfin.yaml

# 5. Deploy core infrastructure (existing playbook)
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes_stack.yaml

# 6. Deploy applications
ansible-playbook -i ansible/inventory.txt ansible/plays/jellyfin.yml
```

### Method 2: Using the Selectable Deployment Script

Edit `update_and_deploy.sh` to uncomment desired playbooks:

```bash
# Edit the script
nano update_and_deploy.sh

# Uncomment desired entries in PLAYBOOKS array:
PLAYBOOKS=(
    "ansible/subsites/01-checks.yaml"        # Enable preflight checks
    # "ansible/subsites/02-certs.yaml"       # Enable certificate generation
    # "ansible/subsites/03-monitoring.yaml"  # Enable monitoring checks
    # "ansible/subsites/04-jellyfin.yaml"    # Enable Jellyfin pre-checks
    # "ansible/site.yaml"                    # Enable full deployment
)

# Run selected playbooks
./update_and_deploy.sh
```

### Method 3: Full Site Orchestration

```bash
# Run all subsites plus core deployment
ansible-playbook -i ansible/inventory.txt ansible/site.yaml

# Check what would be executed
ansible-playbook -i ansible/inventory.txt ansible/site.yaml --check --diff
```

## Validation and Safety

All playbooks support Ansible's safety modes:

```bash
# Syntax validation
ansible-playbook --syntax-check <playbook>

# Check mode (dry run)
ansible-playbook --check <playbook>

# Check mode with diff output
ansible-playbook --check --diff <playbook>

# Verbose output for troubleshooting
ansible-playbook -vv <playbook>
```

## Monitoring Files Inventory

The modular architecture identifies these monitoring-related components:

### Core Monitoring Deployment
- `ansible/plays/kubernetes/deploy_monitoring.yaml` - Main Helm-based monitoring stack deployment
- `ansible/subsites/03-monitoring.yaml` - Pre-checks and requirements validation

### Monitoring Scripts
- `scripts/diagnose_monitoring_permissions.sh` - Permission diagnostics
- `scripts/fix_monitoring_permissions.sh` - Automated permission fixes
- `scripts/validate_monitoring.sh` - Deployment validation
- `scripts/validate_k8s_monitoring.sh` - Kubernetes-specific validation

### Embedded Configuration
The monitoring stack uses embedded Helm values in `deploy_monitoring.yaml` for:
- kube-prometheus-stack (Prometheus, Grafana, AlertManager)
- loki-stack (Loki, Promtail)
- ServiceMonitor creation
- Grafana dashboard provisioning

## Design Principles

### Agent Rules and Constraints

This repository was refactored following strict guidelines for automated agents:

#### Required Rules
1. **Never change file ownership or permissions** on remote hosts
2. **Always perform checks only** and provide CLI remediation commands
3. **Support --syntax-check and --check modes** for all playbooks  
4. **Fail with precise remediation steps** for missing dependencies (CRDs, namespaces, directories, ports, SELinux contexts)
5. **Use user-editable PLAYBOOKS array** with entries commented out by default
6. **Keep idempotent and non-destructive** scaffolding

#### Example Remediation Output
When checks fail, playbooks provide precise commands:

```
Missing monitoring directory. To create it, run on each host:

sudo mkdir -p /srv/monitoring_data
sudo chown root:root /srv/monitoring_data  
sudo chmod 755 /srv/monitoring_data

Why this is needed: Persistent volumes and monitoring services need this directory for data storage.
```

## Troubleshooting

### Common Issues

**Variable undefined errors**: Ensure group_vars or inventory defines required variables like `enable_tls`, `jellyfin_enabled`.

**Host pattern not found**: Run playbooks from masternode with appropriate inventory file or use `-i localhost,` for localhost-only plays.

**kubectl missing**: Follow the provided installation commands in the playbook output.

**Permission denied**: Check SSH keys and become access. Use the remediation commands provided by 01-checks.yaml.

### Failure Modes and Remediation

- **Templating recursion detected**: Remove self-references and use `when: not (var | default(true))` in skip tasks
- **kubectl missing or too-old**: Use distro-appropriate install commands, never attempt automated installation
- **Target host patterns missing**: Run playbooks from masternode with `-i localhost,` or provide inventory file

## Jellyfin Scheduling

Jellyfin is kept scheduled to the storage node `storagenodet3500` (192.168.4.61) via `nodeName` in manifests. The modular architecture preserves this scheduling logic and validates storage node availability during pre-checks.

## Integration with VMStation

This modular deployment integrates with the existing VMStation Kubernetes infrastructure:
- **Monitoring**: Uses existing Prometheus/Grafana stack
- **Storage**: Leverages existing storage node setup
- **Network**: Works with established network configuration
- **Security**: Follows VMStation security patterns

The deployment maintains compatibility with existing automation and monitoring while providing enterprise-grade modularity and safety.