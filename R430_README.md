# Dell R430 - Compute Engine

The Dell R430 serves as the compute engine for the network. It hosts Kubernetes nodes and Docker containers to provide services like Jellyfin for media streaming.

## Features
- **Kubernetes Nodes**: Hosts various applications.
- **Docker Containers**: Runs lightweight services.
- **64GB RAM**: High-performance compute capabilities.

## Setup Instructions
1. **Install Kubernetes**:
   ```bash
   curl -sfL https://get.k3s.io | sh -
   ```

2. **Join the Cluster**:
   - Use the Mini PC as the control plane:
     ```bash
     curl -sfL https://get.k3s.io | K3S_URL=https://<MiniPC_IP>:6443 K3S_TOKEN=<NODE_TOKEN> sh -
     ```

3. **Deploy Applications**:
   - Use Ansible playbooks to deploy applications like Jellyfin:
     ```bash
     ansible-playbook -i inventory.txt ansible/plays/deploy_apps_with_helm.yaml
     ```

4. **Firewall Configuration**:
   ```bash
   sudo ufw allow 32002/tcp  # Jellyfin
   sudo ufw enable
   ```

## Notes
- Ensure the R430 has a static IP address.
- Use the `TODO.md` file for pending tasks.