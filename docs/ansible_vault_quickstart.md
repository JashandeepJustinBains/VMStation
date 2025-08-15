# Ansible Vault & Git Repo Quickstart

This guide helps you securely manage secrets and sync your configuration repo across your desktop and server machines.

---

## 1. Clone Your Repo to a Safe Location

**Recommended folder (Linux):**
- `/opt/vmstation` or `$HOME/vmstation`

**Clone Command:**
```bash
# On each machine (not Desktop folder)
git clone https://github.com/yourusername/vmstation.git /opt/vmstation
cd /opt/vmstation
```

---

## 2. Ansible Vault Quickstart

**Create a Vault-encrypted file:**
```bash
ansible-vault create secrets.yml
```
- Enter a password when prompted.
- Add secrets in YAML format:
```yaml
api_key: mysecretkey
password: mypassword
```

**Edit an existing Vault file:**
```bash
ansible-vault edit secrets.yml
```

**View a Vault file:**
```bash
ansible-vault view secrets.yml
```

**Use Vault file in playbooks:**
```yaml
vars_files:
  - secrets.yml
```

**Run playbook with Vault password prompt:**
```bash
ansible-playbook playbook.yml --ask-vault-pass
```

**Best Practices:**
- Add `secrets.yml` to `.gitignore` so it’s not pushed to git.
- Share the vault password securely (not in git).
- Use the same repo structure on all machines for consistency.

---

## 3. .gitignore Example
```
secrets.yml
*.vault
```
