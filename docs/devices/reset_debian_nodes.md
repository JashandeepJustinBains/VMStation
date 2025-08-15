# Resetting Debian Nodes (MiniPC & T3500) to Default State

This guide provides an Ansible playbook to remove non-system apps and custom network settings from your Debian nodes (MiniPC, T3500).

## Inventory Example (Best Practice)
Do not hardcode static IPs in files tracked by git. Instead, store them in an encrypted Ansible Vault file or a local secrets file that is excluded from git.

**Example: secrets/inventory.yml (add to .gitignore)**
```yaml
debian_nodes:
  minipc:
    ansible_host: 192.168.4.63
    ansible_user: youruser
  nas:
    ansible_host: 192.168.4.61
    ansible_user: youruser
  desktop:
    ansible_host: 192.168.4.32
    ansible_user: youruser
  r430_idrac:
    ansible_host: 192.168.4.60
    ansible_user: youruser
  r430:
    ansible_host: 192.168.4.62
    ansible_user: youruser
```

**Encrypt with Ansible Vault:**
```bash
ansible-vault encrypt secrets/inventory.yml
```

**Import into playbooks:**
```yaml
vars_files:
  - secrets/inventory.yml
```

**Access in playbooks:**
```yaml
- hosts: "{{ debian_nodes.keys() | list }}"
  vars:
    ansible_host: "{{ debian_nodes[inventory_hostname].ansible_host }}"
    ansible_user: "{{ debian_nodes[inventory_hostname].ansible_user }}"
  # ...existing code...
```

**.gitignore Example:**
```
secrets/
*.vault
```

This keeps your IPs and credentials secret from git users, but available locally for automation and playbooks.

## Playbook Example
```yaml
- hosts: debian_nodes
  become: true
  tasks:
    - name: Remove Tailscale
      apt:
        name: tailscale
        state: absent
      ignore_errors: true
    - name: Remove Keepalived
      apt:
        name: keepalived
        state: absent
      ignore_errors: true
    - name: Remove custom Tailscale interface config
      file:
        path: /etc/network/interfaces.d/tailscale
        state: absent
      ignore_errors: true
    - name: Remove custom Keepalived config
      file:
        path: /etc/keepalived/keepalived.conf
        state: absent
      ignore_errors: true
    - name: Remove k3s
      command: "/usr/local/bin/k3s-uninstall.sh"
      args:
        removes: /usr/local/bin/k3s-uninstall.sh
      ignore_errors: true
    - name: Remove k3s agent
      command: "/usr/local/bin/k3s-agent-uninstall.sh"
      args:
        removes: /usr/local/bin/k3s-agent-uninstall.sh
      ignore_errors: true
    - name: Remove other non-essential packages
      apt:
        name:
          - docker.io
          - docker-compose
          - podman
        state: absent
      ignore_errors: true
    - name: Install Podman (optional)
      apt:
        name: podman
        state: present
      ignore_errors: true
    - name: Run Prometheus Node Exporter (Podman)
      command: "podman run -d --name node_exporter -p 9100:9100 prom/node-exporter"
      ignore_errors: true
    - name: Run Grafana Loki Agent (Podman)
      command: "podman run -d --name loki_agent -p 3100:3100 grafana/loki"
      ignore_errors: true
    - name: Reboot node (optional)
      reboot:
        msg: "Rebooting to apply clean state."
        pre_reboot_delay: 5
      when: ansible_facts['os_family'] == 'Debian'
```

## Tips
- Review package list before running to avoid removing needed apps.
- Use Ansible Vault for credentials.
- R430 (RHEL) is not affected by this playbook.
