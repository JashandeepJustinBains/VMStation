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
