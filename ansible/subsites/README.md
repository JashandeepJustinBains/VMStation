VMStation ansible subsites

This directory contains modular sub-playbooks that can be run independently.

How to run:

  ansible-playbook -i ansible/inventory.txt ansible/subsites/01-checks.yaml --check
  ansible-playbook -i ansible/inventory.txt ansible/subsites/03-monitoring.yaml --syntax-check
  ansible-playbook -i ansible/inventory.txt ansible/subsites/05-extra_apps.yaml --check

Design rules:
- Playbooks must only check permissions and preconditions. They must NOT change ownership or file permissions on remote hosts.
- If a task requires elevated privileges or missing local directories, the playbook prints exact CLI remediation commands for the operator to run.

Available subsites:
- 01-checks.yaml: Preflight checks (SSH, become access, firewall)
- 02-certs.yaml: Certificate management
- 03-monitoring.yaml: Monitoring stack pre-checks
- 04-jellyfin.yaml: Jellyfin deployment pre-checks
- 05-extra_apps.yaml: Extra applications (Kubernetes Dashboard, Drone CI, MongoDB)
