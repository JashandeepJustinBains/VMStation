# Git Clone & Update Quickstart

This guide explains how to install git and clone your homelab/server stack repository to all machines, plus how to keep it updated.

---

## 1. Install Git

### Debian/Ubuntu
```bash
sudo apt update
sudo apt install git -y
```

### RHEL/CentOS
```bash
sudo dnf install git -y
```

---

## 2. Clone Your Repository

Replace `<your-repo-url>` with your actual repository URL.

```bash
git clone <your-repo-url> /opt/vmstation
cd /opt/vmstation
```
- Use `/opt/vmstation` or `$HOME/vmstation` for a secure location.

---

## 3. Update Your Repository

To pull the latest changes:
```bash
git pull
```

---

## 4. Automate with Ansible (Optional)

You can use Ansible to automate git installation and repo cloning on all machines:

```yaml
- hosts: all
  become: true
  tasks:
    - name: Install git
      apt:
        name: git
        state: present
      when: ansible_facts['os_family'] == 'Debian'
    - name: Install git (RHEL)
      dnf:
        name: git
        state: present
      when: ansible_facts['os_family'] == 'RedHat'
    - name: Clone repo
      git:
        repo: '<your-repo-url>'
        dest: /opt/vmstation
        update: yes
```

---

## Tips
- Never commit secrets or credentials to your repo.
- Use `.gitignore` to exclude sensitive files.
- Use Ansible Vault or HashiCorp Vault for secret management.
