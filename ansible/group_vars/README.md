# Group Vars

Cluster-level variables used by playbooks.

- Global: `all/`
- Environment or group specific vars can be added as needed

## Secrets

- Store sensitive values encrypted using Ansible Vault.
- Example: `group_vars/all/secrets.yml` (vault-encrypted)
- Reference in playbooks via `vars_files` or direct variable usage.

## Notes

- Align container UIDs with directory ownerships for Prometheus (65534), Loki (10001), Grafana (472).
- FQDNs should be used for headless services in Grafana datasources.
