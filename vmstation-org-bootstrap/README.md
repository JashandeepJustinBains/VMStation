# VMStation Organization Bootstrap

This document provides a comprehensive guide for splitting your monorepo into multiple repositories under a GitHub organization, as well as scaffolding a dedicated machine configuration version control repository to combat configuration drift and ensure stable, reproducible setups.

---

## 1. Machine Configuration Version Control Repo Scaffold

### Purpose
This repository tracks and enforces the desired state of all critical machine configurations to prevent drift and ensure reliable, repeatable setups across reboots, upgrades, and scaling events.

### Recommended Structure
```
machine-config-repo/
├── README.md
├── hosts/
│   ├── debian12/
│   │   ├── sshd_config
│   │   ├── fstab
│   │   ├── interfaces
│   │   └── systemd-networkd/
│   ├── rhel10/
│   │   ├── sshd_config
│   │   ├── fstab
│   │   ├── ifcfg-eth0
│   │   └── NetworkManager/
├── group/
│   ├── common/
│   │   ├── ssh-hardening.conf
│   │   ├── ntp.conf
│   │   └── sysctl.conf
│   └── storage/
│       └── mount-templates/
├── playbooks/
│   ├── apply-config.yml
│   └── validate-config.yml
├── roles/
│   ├── ssh/
│   ├── storage/
│   ├── networking/
│   └── ...
├── inventory/
│   └── hosts.ini
└── scripts/
    ├── gather-config.sh
    └── check-drift.sh
```

### Key Components
- **hosts/**: Per-host configuration files (e.g., `/etc/ssh/sshd_config`, `/etc/fstab`, network configs).
- **group/**: Shared configs for groups of machines (e.g., all storage nodes, all web servers).
- **playbooks/**: Ansible playbooks (or similar) to apply and validate configurations.
- **roles/**: Modular Ansible roles for SSH, storage, networking, etc.
- **inventory/**: Ansible inventory for host/group targeting.
- **scripts/**: Helper scripts to gather current configs and check for drift.

### Example: SSH Configuration
- `hosts/debian12/sshd_config` and `hosts/rhel10/sshd_config`: Version-controlled SSH daemon config.
- `roles/ssh/`: Ansible role to enforce SSH settings.
- `playbooks/apply-config.yml`: Playbook to apply SSH config to all hosts.

### Example: Disk Mounts
- `hosts/debian12/fstab` and `hosts/rhel10/fstab`: Version-controlled `/etc/fstab` for persistent mounts.
- `roles/storage/`: Role to ensure correct disk mounts by UUID.
- `group/storage/mount-templates/`: Templates for common mount patterns.

### Example: Networking
- `hosts/debian12/interfaces`: Debian ifupdown static IP and interface config.
- `hosts/debian12/systemd-networkd/*.network`: Debian systemd-networkd configs (if used).
- `hosts/rhel10/ifcfg-eth0`: RHEL10 legacy network script (if used).
- `hosts/rhel10/NetworkManager/`: RHEL10 NetworkManager keyfiles (if used).
- `roles/networking/`: Role to enforce network settings for each OS.

### Drift Detection
- `scripts/check-drift.sh`: Script to compare live configs vs. repo.
- `playbooks/validate-config.yml`: Playbook to check for drift and report.

### Getting Started
1. Use your GitHub AI CLI to gather current configs:
   - SSH: `cat /etc/ssh/sshd_config`
   - FSTAB: `cat /etc/fstab`
   - Debian 12 Network (ifupdown): `cat /etc/network/interfaces`
   - Debian 12 Network (systemd-networkd): `cat /etc/systemd/network/*.network`
   - RHEL10 NetworkManager: `nmcli connection show` and `cat /etc/NetworkManager/system-connections/*`
   - RHEL10 legacy: `cat /etc/sysconfig/network-scripts/ifcfg-*`
2. Place these files under the appropriate `hosts/` subdirectory.
3. Write Ansible roles/playbooks to enforce these configs.
4. Use CI/CD or scheduled jobs to validate and re-apply as needed.

### Best Practices
- Use Ansible, SaltStack, or similar for idempotent config enforcement.
- Store only non-sensitive configs in the repo; use secrets management for credentials.
- Document each config file’s purpose in `README.md`.
- Use templates and variables for reusable configs.

### References
- [GitOps for Infrastructure](https://www.weave.works/technologies/gitops/)
- [Ansible Best Practices](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- [Infrastructure as Code](https://martinfowler.com/bliki/InfrastructureAsCode.html)

---

## 2. Monorepo Splitting and Migration Strategy

Splitting your monorepo into multiple repositories under a GitHub organization is a good strategy for improving organization, scalability, and AI usability (due to context/memory limits). Here’s a recommended approach based on your workspace structure and project domains:

### Suggested Repo Breakdown

**a. Cluster & Networking (Kubernetes Core)**
- Kubespray integration, cluster manifests, networking configs, CNI plugins, inventory files.
- Example repo: `vmstation-cluster`

**b. Infrastructure Layer**
- NTP/Chrony, Syslog, Kerberos/FreeIPA, infrastructure manifests, Ansible roles/playbooks for infra.
- Example repo: `vmstation-infrastructure`

**c. Monitoring & Observability**
- Prometheus, Grafana, Loki, dashboards, exporters, monitoring manifests, related scripts.
- Example repo: `vmstation-monitoring`

**d. Applications Layer**
- Media servers (Jellyfin), lab apps, custom workloads, application manifests.
- Example repo: `vmstation-apps`

**e. Automation & Tooling**
- Scripts for deployment, validation, diagnostics, CI/CD, Terraform for lab VMs.
- Example repo: `vmstation-tools`

**f. Documentation**
- Optionally, a separate repo for docs, or keep docs in each repo.

### Migration Steps

1. **Create a GitHub Organization** (e.g., `vmstation-org`).
2. **Create new repos** for each logical section.
3. **Move code**: Use `git filter-repo` or `git subtree split` to preserve history for each section, or copy files if history is not critical.
4. **Update CI/CD**: Adjust workflows to work with new repo structure.
5. **Cross-link repos**: Use GitHub topics, README links, and organization-level documentation.
6. **Update documentation**: Make clear which repo is for what, and how they interoperate.

### Benefits

- **AI/LLM Usability**: Smaller repos fit within context windows, making code navigation and suggestions more accurate.
- **Separation of Concerns**: Teams or tools can focus on specific layers.
- **Easier Maintenance**: Updates, issues, and PRs are more targeted.
- **Modular Adoption**: Others can use only the infra, monitoring, or apps layers if desired.

### Potential Drawbacks

- **Cross-repo dependencies**: Need clear versioning and integration points.
- **Initial migration effort**: Some scripts and docs will need updating.

### Example Structure

```
vmstation-org/
├── vmstation-cluster
├── vmstation-infrastructure
├── vmstation-monitoring
├── vmstation-apps
├── vmstation-tools
└── vmstation-docs (optional)
```

### References
- [git-split-repo guide](https://github.com/newren/git-filter-repo)
- [Monorepo vs Polyrepo](https://martinfowler.com/bliki/Monorepo.html)

---

## 3. Example: GitHub AI CLI Scraping Command for Baseline Collection

On your masternode (with SSH access to all machines and the Cisco switch), you can use the following script to gather SSH configs, keys, and baseline system configs from all nodes defined in your Ansible inventory:

```sh
# Parse hostnames from your Ansible inventory and collect configs
HOSTS="masternode storagenodet3500 homelab cisco3650"

for host in $HOSTS; do
  ssh $host 'cat /etc/ssh/sshd_config' > ./hosts/$host/sshd_config
  ssh $host 'cat /etc/ssh/ssh_config' > ./hosts/$host/ssh_config 2>/dev/null || true
  ssh $host 'cat /etc/ssh/ssh_host_*_key.pub' > ./hosts/$host/ssh_host_keys.pub 2>/dev/null || true
  ssh $host 'cat /etc/fstab' > ./hosts/$host/fstab
  # Debian 12
  ssh $host 'cat /etc/network/interfaces' > ./hosts/$host/interfaces 2>/dev/null || true
  ssh $host 'cat /etc/systemd/network/*.network' > ./hosts/$host/systemd-networkd.network 2>/dev/null || true
  # RHEL10
  ssh $host 'cat /etc/sysconfig/network-scripts/ifcfg-*' > ./hosts/$host/ifcfg-eth0 2>/dev/null || true
  ssh $host 'cat /etc/NetworkManager/system-connections/*' > ./hosts/$host/NetworkManager_connections 2>/dev/null || true
  # Cisco Catalyst 3650 (show running-config for SSH)
  if [ "$host" = "cisco3650" ]; then
    ssh $host 'show running-config | include ssh' > ./hosts/$host/cisco_ssh_config.txt
  fi
done
```

- The HOSTS variable is populated with all hostnames from your actual inventory: masternode, storagenodet3500, homelab, and cisco3650 (add the Cisco switch if not already present).
- This script collects SSH daemon configs, client configs, host public keys, fstab, and network configs for both Debian 12 and RHEL10, and the SSH config from your Cisco switch.
- All files are saved under the appropriate `hosts/` subdirectory for version control.
- You can expand this script to collect any other baseline files you need.

**Note:**
- Ensure your masternode's SSH key is authorized on all targets.
- For the Cisco switch, you may need to adjust the SSH command or use an expect script if interactive login is required.
- Always verify and sanitize collected configs before committing to version control, especially for sensitive key material.

---

## 4. Guiding Principles and Advanced Scraper Design (AI Agent Perspective)

### 1. Leverage Actual Inventory and Repo Structure
- Dynamically parse `ansible/inventory/hosts.yml` to discover all hosts and their groupings (monitoring, storage, compute, etc.).
- Use group membership to determine which configs and services are relevant for each node.

### 2. Output Organization
- Output all collected configs to a dedicated `collected-configs/` directory at the repo root.
- Mirror the repo's logical structure for easy comparison:
  - `collected-configs/hosts/<hostname>/` for per-node configs
  - `collected-configs/group/<groupname>/` for shared configs
  - `collected-configs/apps/<appname>/` for application-specific configs
  - `collected-configs/infra/<servicename>/` for infra services
  - `collected-configs/monitoring/<component>/` for monitoring stack

### 3. What to Collect
- Use Ansible playbooks, roles, and manifests as the source of truth for which files/services to collect.
- For each host, collect:
  - SSH configs and keys (public only)
  - `/etc/fstab`, network configs, and any files referenced in playbooks/roles
  - Application configs for apps/services running on that node
- For each group, collect shared configs (e.g., NTP, sysctl)
- For infra/monitoring/apps, collect live configs from relevant nodes

### 4. Metadata and Provenance
- For each collected file, generate a `.meta.json` with:
  - Hostname, group, timestamp, source path, hash, collector version
- Enables traceability and reproducibility

### 5. Security
- Never collect or store private keys, secrets, or sensitive tokens
- Use `.gitignore` to prevent accidental commits of sensitive files

### 6. Automation
- Provide a script (`scripts/gather-config.sh`) that:
  - Auto-discovers hosts and roles from inventory
  - Runs the appropriate collection commands per host/group
  - Outputs to the correct subdirectory
  - Can be run manually or via cron/systemd timer

### 7. Drift Detection
- Provide a `scripts/check-drift.sh` that:
  - Compares `collected-configs/` with the desired state in `hosts/`, `group/`, etc.
  - Reports differences in a human-readable format

### 8. AI Agent Best Practices
- Always use the inventory and repo structure as the source of truth
- Never hardcode hostnames or paths—parse them dynamically
- Output should be organized, traceable, and easy to compare with desired state
- Document every step and decision in the repo for future maintainers

---

**AI Agent Summary:**
This approach ensures the scraper is robust, extensible, and context-aware, leveraging your actual inventory and repo structure. It enables precise drift detection, safe automation, and easy review, making it ideal for both human and AI-driven operations in your environment.

---

## 5. AI Agent Safeguards and Guiderails

### 1. Strict Inventory Parsing
- Always parse `ansible/inventory/hosts.yml` using a YAML parser, never regex or manual string matching.
- Validate that all discovered hosts are reachable via SSH before attempting collection.
- Log unreachable or misconfigured hosts and skip them safely.

### 2. Output Directory Safety
- Only write to the `collected-configs/` directory at the repo root.
- Never overwrite files in `hosts/`, `group/`, `apps/`, or any version-controlled config directories.
- If a file already exists in `collected-configs/hosts/<hostname>/`, append a timestamp or create a backup before overwriting.

### 3. File Type and Size Controls
- Only collect text-based configuration files (e.g., .conf, .yaml, .json, .ini, .service).
- Skip binary files, device files, or anything over a configurable size limit (e.g., 1MB).
- Log and report any skipped files for review.

### 4. Secrets and Sensitive Data
- Never collect or store private keys, passwords, tokens, or secrets.
- Use a denylist of known sensitive paths (e.g., `/etc/shadow`, `/etc/ssh/*_key`, `/root/.ssh/*`).
- If a file matches a denylist pattern, log the attempt and skip collection.
- Redact any accidental sensitive data in logs and outputs.

### 5. Metadata and Audit Logging
- For every collected file, generate a `.meta.json` with:
  - Hostname, group, timestamp, source path, file hash, collector version, and collection status (success/skipped/failed).
- Maintain a master audit log (`collected-configs/collection_audit.log`) with all actions, errors, and warnings.

### 6. Error Handling and Idempotency
- On error (e.g., SSH failure, permission denied), log the error and continue with the next file/host.
- Never halt the entire collection process due to a single failure.
- Ensure the script can be safely re-run without data loss or corruption.

### 7. Human-in-the-Loop Review
- After each collection run, require a human review of the audit log and collected files before any commit or further automation.
- Provide a summary report of what was collected, skipped, or failed, highlighting any potential issues.

### 8. Change Control and Approval
- Never auto-commit or auto-push collected configs to version control.
- Require explicit human approval for any commit or merge of new collected data.
- Use pull requests and code review for all changes to the desired state or collected configs.

### 9. Documentation and Explainability
- Document every collection rule, denylist, and safeguard in the repo (`README.md` and `scripts/` comments).
- Ensure all AI agent actions are explainable and traceable for future maintainers.

### 10. Continuous Improvement
- Regularly review and update denylist, file type filters, and error handling based on new findings or incidents.
- Encourage feedback from human operators to improve AI agent behavior and safety.

---

**AI Agent Safeguard Summary:**
These guiderails ensure the AI agent operates safely, predictably, and transparently, minimizing risk to your infrastructure and data. All actions are logged, reviewed, and require human approval before affecting version control or production systems.

---

**Summary:**  
Your plan is sound and aligns with best practices for large, multi-domain projects. Splitting by layer (cluster/networking, infra, monitoring, apps, tooling) will make the codebase more manageable for both humans and AI tools.
