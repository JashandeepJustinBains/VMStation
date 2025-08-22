
# VMStation Home Cloud Overview

Welcome to VMStation! The documentation has been reorganized for clarity and maintainability.

## Where to Find Things
- See [docs/README.md](./docs/README.md) for the new documentation index.
- Device-specific guides, stack setup, security, monitoring, and troubleshooting are now in the `docs/` folder.

## Device Roles (2025)
- **T3500**: NAS Server
- **R430**: Compute Engine (Kubernetes/Podman/VMs)
- **Catalyst 3650V02**: Managed Switch (VLANs, QoS)
- **MiniPC**: Monitoring & k3s Controller

## Stack Options
- Kubernetes (k8s), Podman, VMs — see docs/stack/overview.md for recommendations

## Note
Outdated info (e.g., ngrok, old device roles) has been removed. Please refer to the new docs for up-to-date instructions and best practices.

## Base System Setup
Before installing services, ensure:
- Debian Linux (Headless) installed on each node
- Static IP addresses configured
- SSH access enabled

---

## Kubernetes & MicroK8s
Install MicroK8s:
```bash
sudo apt update && sudo apt install microk8s -y
sudo usermod -aG microk8s $USER
sudo microk8s status
microk8s enable dns storage ingress
```
Create alias for kubectl:
```bash
alias kubectl='microk8s kubectl'

## Developer convenience - syntax checks before deploy
This repository includes a helper script to validate Ansible playbooks before running the deploy script.

| Script | Purpose |
|---|---|
| `./update_and_syntax.sh` | Runs `ansible-playbook --syntax-check` on all playbooks under `ansible/plays` and optionally `ansible-lint`/`yamllint` if installed. Run this before `./update_and_deploy.sh` to catch syntax and lint issues early. |
echo "alias kubectl='microk8s kubectl'" >> ~/.bashrc
source ~/.bashrc
```
Check node status:
```bash
microk8s stop
microk8s start
microk8s status --wait-ready
```

---

## Container Images (No Docker)
Export image:
```bash
microk8s ctr images export myapp.tar myapp-image:latest
```
Transfer image:
```bash
scp myapp.tar user@remote-server:/home/user/
```
Import image:
```bash
microk8s ctr images import myapp.tar
```

---

## Ansible Automation
Install Ansible:
```bash
sudo apt install ansible -y
```
Define inventory (`/etc/ansible/hosts`):
```ini
[master]
node1 ansible_host=192.168.1.100
[worker]
node2 ansible_host=192.168.1.101
node3 ansible_host=192.168.1.102
```
Test connection:
```bash
ansible all -m ping
```
Sample playbook:
```yaml
- hosts: microk8s
  tasks:
    - name: Install MicroK8s
      apt:
        name: microk8s
        state: present
    - name: Load container image
      command: microk8s ctr images import /home/user/myapp.tar
    - name: Deploy app
      command: microk8s kubectl apply -f /home/user/deployment.yaml
```
Run playbook:
```bash
ansible-playbook deploy_microk8s.yaml
```

---

## Monitoring & Logging
Stack: Grafana, Prometheus, Loki
See `site.yaml` and `deploy.sh` for setup details.

---

## Firewall & Security
Harden exposed nodes (e.g., via DuckDNS):
```bash
sudo apt install ufw fail2ban
sudo ufw default deny incoming
sudo ufw allow ssh
sudo ufw enable
sudo systemctl enable fail2ban
```
Set Fail2Ban rules to prevent brute-force attacks.

---

## ngrok Tunnel
On worker node:
```bash
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc |
  sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null &&
  echo "deb https://ngrok-agent.s3.amazonaws.com buster main" |
  sudo tee /etc/apt/sources.list.d/ngrok.list &&
  sudo apt update &&
  sudo apt install ngrok
```

---

## Useful kubectl Commands
```bash
kubectl get ns
kubectl get pods -n [namespace] {-A, --watch, -o wide}
kubectl get nodes -o wide
kubectl get svc --all-namespaces | grep NodePort
kubectl get svc --all-namespaces -o wide
```

---

## TODO
- Set up cluster Grafana, Prometheus, Ansible, Drone, Loki, and more
- Finalize kubeconfig secret formatting for Drone CI
- Split documentation into sub-documents for each device
- Harden SSH and firewall rules
- Document troubleshooting steps for CI and registry
