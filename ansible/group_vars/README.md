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

## Secrets layout and recommended variables

- `group_vars/all/secrets.yml` (vault-encrypted): Global secrets file. Suggested variables:
	- `prometheus_retention_secret`: used for any remote write credentials (if applicable)
	- `ipmi_exporter_username`, `ipmi_exporter_password`: used by IPMI exporter configuration (do not hardcode)
	- `freeipa_admin_password`: FreeIPA/kerberos admin password (vault only)

## Operational notes

- If persistent volumes are pre-provisioned, ensure the underlying storage has the correct ownership (see UIDs above) or run `scripts/fix-monitoring-permissions.sh` to remediate.
- When editing secrets, use Ansible Vault:

```bash
ansible-vault edit ansible/group_vars/all/secrets.yml
``` 

Keep vault passwords out of version control and use CI secrets or a vault password file stored securely on the operator workstation.
