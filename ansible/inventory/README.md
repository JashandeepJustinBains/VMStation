# Ansible Inventory

Primary cluster inventory and host grouping.

- Main file: `hosts.yml`
- Legacy sample: `hosts`

## Groups

- `kube_control_plane`: Control-plane nodes
- `kube_node`: Worker nodes
- `etcd`: etcd members (often control plane)
- `monitoring`: Nodes running monitoring stack

## Best Practices

- Keep hostnames and IPs consistent with DNS reverse lookup.
- For RHEL nodes, ensure `ansible_user` and `become` are configured.
- Do not commit credentials; use Ansible Vault and `group_vars`.

## Nonstandard inventory choices

- `ansible_connection: local` for the masternode
	- Rationale: Some deployment phases run locally on the control plane (packaging artifacts, staging manifests). The masternode entries may use `ansible_connection: local` so playbooks can run tasks directly without SSH when executed on the control plane itself.

- Debian nodes (monitoring/storage) default to `ansible_user: root`
	- Rationale: For a small homelab the simplest operational model was chosen — root SSH simplifies early bootstrap and avoids sudo configuration edge-cases. For production-grade setups switch to a dedicated user with `become` enabled.

- RHEL homelab node uses `ansible_user` + `become` with vault-encrypted password
	- Rationale: RHEL security posture in the environment enforces non-root access; we keep the sudo password in the vault and document the expected variable names in `group_vars/all/README.md`.

- Group labels
	- `monitoring`: Nodes that run monitoring stack components. Playbooks filter by this group to avoid deploying monitoring to the RKE2 homelab unless explicitly requested.
	- `compute_nodes`: Used to target the homelab RKE2 installation separate from the Debian kubeadm cluster.
