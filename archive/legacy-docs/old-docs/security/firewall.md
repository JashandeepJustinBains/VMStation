# Firewall & Security Guide

## UFW Setup
```bash
sudo apt install ufw -y
sudo ufw default deny incoming
sudo ufw allow ssh
sudo ufw enable
```

## Fail2Ban Setup
```bash
sudo apt install fail2ban -y
sudo systemctl enable fail2ban
```

## SSH Hardening
- Disable root login
- Use key-based authentication
- Change default port if needed
