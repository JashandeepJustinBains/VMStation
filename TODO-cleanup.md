```markdown
- [ ] A: Prune legacy/outdated scripts, docs, and playbooks
  - Goal: Remove obsolete shell scripts and duplicate playbooks from `scripts/` and consolidate behavior into idempotent Ansible roles.
  - Success criteria: `scripts/` contains only lightweight helpers and docs; all major operational workflows are driven by `ansible/roles/*` and `ansible/playbooks/*`.

- [ ] B: Implement WOL idle-sleep and Grafana visibility
  - Goal: Deploy an hourly idle-check on `masternode` that writes a Prometheus textfile metric and optionally sends WOL packets to worker nodes.
  - Success criteria: `vmstation_idle` metric appears in Prometheus; Grafana dashboard visualizes node idle state; worker nodes can be woken via WOL and spun down when idle.

Notes:
- Branch: `minimal-deploy` contains the current refactor and an initial `idle-sleep` role scaffold. Backups are on `main_broken_20251001`.
- Secrets: ensure any MACs or passwords are stored in `ansible/inventory/group_vars/secrets.yml` encrypted with ansible-vault.

``` 
