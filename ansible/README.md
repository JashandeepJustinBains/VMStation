# Ansible

Automation entrypoint for VMStation deployments.

- Inventory: `inventory/hosts.yml`
- Playbooks: `playbooks/`
- Roles: `roles/`
- Group variables: `group_vars/`
- Files and templates: `files/`

## Usage

Run playbooks using Linux/macOS shells or WSL; Windows PowerShell users should run within WSL for best compatibility.

Examples:

- Verify cluster:
  - `ansible-playbook -i inventory/hosts.yml playbooks/verify-cluster.yaml`
- Deploy monitoring stack:
  - `ansible-playbook -i inventory/hosts.yml playbooks/deploy-monitoring-stack.yaml`

## Requirements

- Ansible 2.15+
- Python 3.10+
- kubectl v1.29+

## Notes

- Do not store secrets in plaintext. Use Ansible Vault and reference variables from `group_vars/all/`.
- All scripts target Linux nodes (Kubernetes on Debian/RHEL); ensure `become` privileges are configured.
