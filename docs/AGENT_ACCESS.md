# Granting Controlled Access for Automation Runner

This document explains how to safely provision a control host (self-hosted runner) and grant limited access so an automation agent or CI can run Kubespray/Ansible against your 192.168.4.0/24 hosts.

Overview
- The repo contains `ansible/playbooks/provision-runner.yml` (Ansible playbook) and `scripts/provision-runner.sh` (bootstrap script).
- Use these to prepare a Linux control host that has network reachability to your nodes.

High-level steps
1. Choose a Linux host on the same network as your nodes (192.168.4.x).
2. Run the Ansible playbook locally or execute `scripts/provision-runner.sh` as root to bootstrap.
3. Copy the generated public key (`/home/vmstation-ops/.ssh/id_vmstation_ops.pub`) to each target host's `~/.ssh/authorized_keys` for the user listed in `ansible/inventory/hosts.yml`.
4. Verify connectivity:
   ansible -i ansible/inventory/hosts.yml all -m ping --user <ansible_user>

Security guidance
- Never commit private keys into git. Keep the private key on the control host or in a vault/CI secret.
- The playbook gives limited passwordless sudo for necessary automation commands only.
- Use Ansible Vault for sensitive variables and configure `ansible.cfg` to point to the vault password file or CI secrets.

If you want, I can now:
- Generate a recommended `ansible.cfg` snippet, `ansible/hosts.example`, and a small check-playbook that tests connectivity and runs the Kubespray preflight.
- Or, I can wait for you to run the bootstrap on a control host and paste me the connectivity test outputs so I can proceed to the Kubespray automation.
