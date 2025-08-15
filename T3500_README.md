# T3500 - Pseudo NAS Server

The T3500 serves as a pseudo NAS server for the network. It provides centralized storage for media and other files, accessible to all devices on the network.

## Features
- **Centralized Storage**: Shares media and files across the network.
- **Samba**: Provides file-sharing capabilities.
- **Docker**: Hosts lightweight services if needed.

## Setup Instructions
1. **Install Samba**:
   ```bash
   sudo apt update && sudo apt install -y samba
   ```

2. **Configure Samba**:
   - Edit `/etc/samba/smb.conf` to add shared directories:
     ```ini
     [Media]
     path = /mnt/media
     browseable = yes
     read only = no
     guest ok = yes
     ```

3. **Start Samba**:
   ```bash
   sudo systemctl restart smbd
   ```

4. **Optional - Install Docker**:
   ```bash
   sudo apt install -y docker.io
   ```

## Notes
- Ensure the T3500 has a static IP address.
- Use the `TODO.md` file for pending tasks.