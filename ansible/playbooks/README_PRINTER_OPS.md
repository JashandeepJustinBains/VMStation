# README for printer-ops Ansible playbook

This playbook automates creation of PVs, PVCs, namespace, and deployment of CUPS/Avahi and Samba for Brother printer scan-to-file and AirPrint support.

Usage:

1. Ensure your inventory defines the groups `storage_nodes` (contains storagenodet3500) and `monitoring_nodes` (contains masternode with local connection).
2. Run the playbook from the repository root on the control machine (masternode):

```bash
ansible-playbook -i inventory.ini ansible/playbooks/printer-ops.yml
```

What it does:
- Creates /srv/paperless-input and /srv/scan-storage on storagenodet3500
- Creates printer-ops namespace
- Applies PV/PVC manifests and Deployments/Services in manifests/printer/

Security notes:
- Replace the SAMBA_PASS placeholder with a secure value and convert to a Kubernetes Secret if desired.
- The CUPS and Samba deployments use hostNetwork: true to allow mDNS and direct SMB exposure; review network and firewall rules before enabling.
