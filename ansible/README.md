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

Note: Some playbooks (for example `playbooks/jellyfin.yml`) now include a small pre-task that will
attempt to ensure the Python `kubernetes` client package is present on target nodes by installing
`python3-pip` and `kubernetes` via `pip3`. This is a convenience to make those playbooks runnable
on freshly provisioned nodes without requiring extra ad-hoc steps. If your environment is strictly
offline, populate a local wheelhouse and modify playbook execution accordingly (contact the repo
maintainer for wheelhouse guidance).

## Notes

- Do not store secrets in plaintext. Use Ansible Vault and reference variables from `group_vars/all/`.
- All scripts target Linux nodes (Kubernetes on Debian/RHEL); ensure `become` privileges are configured.

## Uncommon choices & rationale

This project makes several non-default or opinionated choices to support a reliable, reproducible homelab environment. These are deliberate and documented here so operators understand the why behind the code.

- Container UID to PV ownership mapping
  - Rationale: Many upstream Helm charts assume filesystem ownerships; during troubleshooting we observed permission-related CrashLoopBackOffs for Prometheus and Loki. To avoid host-level chown loops and simplify restoration, persistent volumes are created and owned by specific UIDs. Key mappings:
    - Prometheus: UID 65534 (nobody/65534) — reduces privilege needs and aligns with common Prometheus images
    - Loki: UID 10001 — matches Loki container default runtime user in this deployment
    - Grafana: UID 472 — matches Grafana upstream Docker UID used in packaged images
  - Operational note: Playbooks set filesystem ownership where necessary. If PVs are pre-provisioned, ensure PVC-backed storage has correct ownership or run the included remediation script `scripts/fix-monitoring-permissions.sh`.

- Headless services and DNS FQDNs
  - Rationale: Several components (Grafana datasources, Loki clients) communicate with headless services. Short service names (e.g., `loki`) can resolve inconsistently depending on client pod DNS search paths. We therefore standardize on full cluster DNS names (FQDNs) for critical datasources and cross-namespace access:
    - Example: `prometheus.monitoring.svc.cluster.local:9090`
  - Operational note: This reduces intermittent DNS lookup failures and makes multi-namespace communication deterministic.

- Separation: Kubespray (kubeadm) vs RKE2
  - Rationale: RKE2 is used only on the homelab RHEL10 node as an isolated, optional cluster. Mixing kubeadm and RKE2 on the same control-plane causes operational complexity. The repo intentionally keeps RKE2 deployments separate to allow independent lifecycle management and easier troubleshooting.

- Containerd socket resilience
  - Rationale: The preflight and install playbooks include extra retries and multiple package strategies for `containerd` socket availability. Some RHEL environments (and certain cloud images) present transient states where systemd unit activation or container runtime install order causes the socket to be missing. The playbooks therefore wait for the socket, attempt alternative install paths, and capture diagnostics to `ansible/artifacts/` on failure.

- Windows host development workflow
  - Rationale: The author develops on Windows but targets Linux/Kubernetes servers. To avoid Windows-related shell differences (line endings, shell builtin semantics) all operational scripts are documented and tested for WSL/WSL2. The README explicitly recommends running playbooks from WSL for consistent behavior.

- No hardcoded credentials; Ansible Vault usage
  - Rationale: This repo runs in mixed-privilege environments and sometimes handles domain-like services (FreeIPA/Kerberos) where secrets leakage is high-risk. Vault-encrypted variables are required for any credentials; sample variable names and locations are documented in `ansible/group_vars/all/README.md`.

If you'd like, I can extract these rationale sections into a short 'DESIGN.md' under `docs/` and link to it from the root README.

For a single reference of these choices see `docs/DESIGN.md`.
