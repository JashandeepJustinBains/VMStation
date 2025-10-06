# HashiCorp Vault Usage Guide

This guide outlines how to use HashiCorp Vault for self-hosted credential management in your homelab, with a TODO for advanced security features.

---

## 1. Simple Self-Hosted Credential Management

### What is Vault?
HashiCorp Vault is a tool for securely storing, managing, and accessing secrets (passwords, API keys, certificates) in a centralized, encrypted service.

### Basic Setup Steps
1. **Install Vault**
   - On your chosen server (MiniPC, T3500, or R430):
     ```bash
     sudo apt update
     sudo apt install vault
     # Or download from https://www.vaultproject.io/downloads
     ```
2. **Start Vault in Dev Mode (for testing):**
   ```bash
   vault server -dev
   ```
   - For production, initialize and unseal Vault, set up storage backend (file, Consul, etc.).
3. **Access Vault UI or CLI:**
   - Web UI: http://<vault-server-ip>:8200
   - CLI: `vault login <token>`
4. **Store a Secret:**
   ```bash
   vault kv put secret/myapp username=admin password=supersecret
   ```
5. **Read a Secret:**
   ```bash
   vault kv get secret/myapp
   ```
6. **Integrate with Ansible:**
   - Use the `community.hashi_vault` collection to fetch secrets in playbooks.
   - Example:
     ```yaml
     - name: Fetch secret from Vault
       community.hashi_vault.vault_read:
         url: http://<vault-server-ip>:8200
         token: <vault-token>
         secret: secret/myapp
     ```

---

## 2. TODO: Advanced Security Features
- [ ] Set up SAML authentication for Vault login
- [ ] Integrate with LDAP/Active Directory
- [ ] Use X.509 certificates for authentication
- [ ] Enable audit logging and access policies
- [ ] Move towards Zero Trust Network Architecture (ZTNA)

---

## References
- [Vault Documentation](https://www.vaultproject.io/docs)
- [Vault UI & API](https://www.vaultproject.io/docs/commands/ui)
- [Ansible Vault Integration](https://docs.ansible.com/ansible/latest/collections/community/hashi_vault/index.html)
