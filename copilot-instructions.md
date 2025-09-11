Configure instructions for this repository as documented in [Best practices for Copilot coding agent in your repository](https://gh.io/copilot-coding-agent-tips).

<Onboard this repo>

Purpose
- Help an automated coding/assist agent (Copilot coding agent) work productively and safely in this repository.
- Provide quick context, key files, allowed actions, validation steps and a small contract the agent should follow.

Repository layout (high level)
- `ansible/` : Ansible playbooks, inventory and group_vars used to deploy and configure the monitoring stack.
- `ansible/group_vars/` : global variables. `all.yml` is the primary file Ansible auto-loads.
- `ansible/plays/monitoring/` : monitoring playbooks (Prometheus, Grafana, Loki, Promtail, local registry).
- `ansible/files/` : Grafana dashboards and other static assets copied to targets.
- `scripts/` : helpers and validators (e.g., `validate_monitoring.sh`).

Agent onboarding checklist (short)
1. Read this file and `ansible/group_vars/all.yml` before proposing changes that affect deployment.
2. Never check in plaintext secrets. If a change requires credentials, recommend using `ansible-vault` and show the exact vault keys to add.
3. Prefer edits to templates, playbooks and non-secret group_vars. For secret values, add a vault template or instructions only.
4. When making changes that touch deploy/run flows, add or update a short validation step (command or script) and a one-line smoke test.

Contract (inputs / outputs / success criteria)
- Inputs: the repository files and inventory at `ansible/inventory.txt`, local control host is Windows PowerShell (repo root: `F:\VMStation`).
- Outputs: idempotent Ansible playbooks and helper scripts that will deploy monitoring stack to inventory hosts; documentation and tests for those flows.
- Success: Playbooks run in check-mode without errors (`ansible-playbook -C -vv ...`) and real runs succeed with Grafana, Prometheus and Loki containers started on the monitoring node.

Key repo-specific rules and conventions
- The control machine uses PowerShell (Windows). When suggesting terminal commands, format them for PowerShell.
- `ansible/group_vars/all.yml` is authoritative for defaults; secrets must live in `ansible/group_vars/*.yml` encrypted by `ansible-vault` (e.g. `secrets.yml`).
- Do not modify `ansible/group_vars/all.yml` to add plaintext passwords; instead propose vault edits.
- Grafana provisioning data is written to `{{ monit_root }}/grafana/...`. `monit_root` default: `/srv/monitoring_data`.

Local monitoring node context (important)
- The repository owner runs playbooks and many commands directly on the monitoring node, which is on a local subnet (LAN). When the user refers to "monitoring node" or runs validation commands, prefer examples that target the monitoring host IP (e.g. `192.168.x.x`) or `localhost` on that machine.
- When providing SSH/scp examples from the control host, clearly indicate replacing the host/IP with the monitoring node address or use the inventory group `monitoring_nodes`.

Kubernetes cluster architecture (important)
- This Kubernetes cluster consists of 3 nodes:
  1. masternode (control-plane) - the monitoring_nodes group (192.168.4.63)
  2. storagenodet3500 (storage_nodes) - worker node (192.168.4.61)  
  3. homelab (compute_nodes) - worker node (192.168.4.62)
- All commands are executed on the masternode only. The other nodes do not have the git repo cloned to them.
- The masternode handles setting up and controlling Kubernetes and related apps/programs/configs for communication and workflow.
- If a script needs to exist on another node, it must be copied to that node and executed, or use `remote_src`.
- The masternode has SSH tokens for the worker nodes, but worker nodes might not have SSH tokens into the masternode.
- The repository is located at `/srv/monitoring_data/VMStation/` on the masternode in production deployments.

Hidden `ansible/group_vars/all.yml` entries (do NOT add secrets here)
The user keeps several variables in `ansible/group_vars/all.yml` but hides secret values for safety. An agent should treat these keys as sensitive and never print their values in plaintext. Common keys present in the file include:
- monit_root
- grafana_port
- prometheus_port
- loki_port
- vault_r430_sudo_password (vaulted in practice)
- samba_password
- enable_podman_exporters
- enable_quay_metrics
- prometheus_scrape_interval
- prometheus_scrape_timeout
- podman_system_metrics_host_port
- quay_username (secret)
- quay_password (secret)
- grafana_admin_pass (secret)
- ansible_become_pass (templated to use the vaulted password)

Guidance when the user says values are hidden:
- Do not attempt to reconstruct or echo secret values. Instead, reference the variable name and instruct the user how to set them (use `ansible-vault create ansible/group_vars/secrets.yml`).
- If a proposed change requires revealing or modifying a secret, instruct the user to perform the update locally or to create/update a vault file; provide the exact vault keys to add but never the values.

Common tasks the agent may perform (and constraints)
- Task: propose or create `ansible/group_vars/all.yml` defaults (allowed): modify only non-secret values and add comments.
- Task: add an Ansible task or template for service deploy (allowed): ensure idempotence and add check-mode support.
- Task: push files to remote node (NOT allowed directly): suggest Ansible `copy`/`template` tasks or provide PowerShell/ssh/scp commands and warn about credentials.
- Task: create a vault template (allowed): create `ansible/group_vars/secrets.yml.example` with variable names and usage instructions; do not store secrets.

Validation and quick commands (PowerShell, run from repo root `F:\VMStation`)
- Check playbook in check-mode (no changes):
```powershell
ansible-playbook -i .\ansible\inventory.txt .\ansible\plays\monitoring_stack.yaml -C -vv
```
- Run full playbook with verbose logging:
```powershell
ansible-playbook -i .\ansible\inventory.txt .\ansible\plays\monitoring_stack.yaml -vv
```
- Validate Grafana health (example):
```powershell
$MONITOR=192.168.4.63; Invoke-RestMethod -Uri "http://$MONITOR:3000/api/health" -UseBasicParsing
```
- Copy local `all.yml` template to control repo (if missing):
```powershell
New-Item -ItemType Directory -Path .\ansible\group_vars -Force
Copy-Item .\ansible\group_vars\all.yml.template .\ansible\group_vars\all.yml -Force
notepad .\ansible\group_vars\all.yml
```

Secrets handling guidance (mandatory)
- Always use `ansible-vault` for secrets. Example workflow (run on control host with ansible installed):
```powershell
ansible-vault create .\ansible\group_vars\secrets.yml
# add: quay_username, quay_password, grafana_admin_pass, vault_r430_sudo_password
```
- Run playbooks with vault prompt or a vault-password-file: `ansible-playbook ... --ask-vault-pass`.
- If the agent suggests secrets, it must instruct the user to create them with `ansible-vault` and never insert real values in the repo.

Diagnostics the agent should run before making changes
- Search for conditional `when:` that could skip Grafana (e.g., checks of `enable_quay_metrics`, custom `enable_grafana`) and report them.
- Validate no duplicate/conflicting settings exist in `ansible/group_vars/all.yml` (e.g., multiple `enable_quay_metrics` values).

What to do when Grafana does not start
1. Check `ansible/group_vars/all.yml` for missing/contradictory vars.
2. Run the monitoring playbook with `-vv` and examine tasks around `Start Grafana container` and `Ensure monitoring Pod exists`.
3. On the monitoring node, check podman: `podman ps -a --filter name=grafana` and `podman logs grafana` (provide PowerShell-friendly SSH command variants).

Files an agent may safely edit or suggest edits for
- `ansible/plays/monitoring/*.yaml` (add checks, logging, idempotence improvements)
- `ansible/templates/*` (rendering templates used by playbooks)
- `ansible/files/*` dashboard JSONs (non-secret content)
- `scripts/validate_monitoring.sh` (improve checks) — update only non-destructive checks

Files an agent must not populate with secrets
- `ansible/group_vars/all.yml`
- Any file whose name contains `secret`, `password`, `vault` unless encrypted

On merge requests / PRs the agent should create
- A short PR description explaining the change, the validation steps (commands above) and a one-line smoke test.
- If changing deployment behaviour, include expected Ansible output snippets and which hosts were tested.

Contact / fallback
- If the agent cannot determine safe defaults, it should ask the user for the exact target host/group and which vars are safe to modify.

Minimal example resources the agent can add (non-secrets)
- `ansible/group_vars/secrets.yml.example` with variable names and comments (no real values).

Last updated: 2025-08-25
