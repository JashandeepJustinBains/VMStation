VMStation ansible subsites

This directory contains modular sub-playbooks that can be run independently.

How to run:

  ansible-playbook -i ansible/inventory.txt ansible/subsites/01-checks.yaml --check
  ansible-playbook -i ansible/inventory.txt ansible/subsites/03-monitoring.yaml --syntax-check

Design rules:
- Playbooks must only check permissions and preconditions. They must NOT change ownership or file permissions on remote hosts.
- If a task requires elevated privileges or missing local directories, the playbook prints exact CLI remediation commands for the operator to run.
