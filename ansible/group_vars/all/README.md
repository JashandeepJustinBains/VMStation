# Group Vars: all

Global variables and secrets (vault-encrypted) for the cluster.

- Store sensitive data in `secrets.yml` and encrypt with Ansible Vault
- Reference variables in playbooks; do not hardcode secrets in manifests or scripts

Example:
- `ansible-vault edit ansible/group_vars/all/secrets.yml`
