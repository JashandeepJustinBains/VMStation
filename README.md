# VMStation
My personal virtual machine cloud computing rig on a minipc
MicroK8s with Ansible Deployment Guide
Optimized for low-resource systems

1. Install microk8s
```
apt install sudo -y
apt install snapd -y
systemctl enable --now snapd
snap version
snap install core
snap install microk8s --classic
```


1. Set Up Your Environment
Install MicroK8s
```
  sudo apt update && sudo apt install microk8s
  sudo usermod -aG microk8s $USER
  sudo microk8s status
```
Enable required services:
```
  microk8s enable dns storage ingress
```
Install Ansible
```  
sudo apt install ansible -y
```
2. Preparing Container Images Without Docker
Save a Container Image
  ```
microk8s ctr images export myapp.tar myapp-image:latest
```  
Transfer Image to Another Machine
```  
scp myapp.tar user@remote-server:/home/user/
```
Load Image into MicroK8s
```  
microk8s ctr images import myapp.tar
```
3. Automate Deployment with Ansible
Create an Ansible Playbook ()
```
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
Run it:
```
  ansible-playbook deploy_microk8s.yaml
```
4. Define Kubernetes Deployment ()
```  
apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: myapp
  spec:
    replicas: 2
    selector:
      matchLabels:
        app: myapp
    template:
      metadata:
        labels:
          app: myapp
      spec:
        containers:
          - name: myapp
            image: myapp-image:latest
```

check status of nodes
```
microk8s stop
microk8s start
microk8s status --wait-ready
```

create alias for 'microk8s kubectl' :
```
alias kubectl='microk8s kubectl'
echo "alias kubectl='microk8s kubectl'" >> ~/.bashrc
source ~/.bashrc
```
###TODO
set up **cluster Grafana, Prometheus, Ansible, Drone, Loki, and more**

---

## **1. Base System Setup**
Before installing services, ensure you have:
**Debian Linux (Headless) installed on each node**  
**Static IP addresses configured for each machine**  
**SSH access enabled across all nodes**  


## **2. useful kubectl commands **
kubectl get ns
kubectl get pods -n [name space] {-A, --watch, -o wide}
kubectl get nodes -o wide
kubectl get svc --all-namespaces | grep NodePort
kubectl get svc --all-namespaces -o wide

## **3. Monitoring: Grafana + Prometheus**
Loki + Grafana + Prometheus tracks **system performance metrics**.
look at ```site.yaml``` and ```deploy.sh```

## **4. Orchestration: Ansible**
Ansible automates **configuration & deployment** across your cluster.

### **Install Ansible**
```bash
sudo apt install ansible
```
✔️ **Define inventory:**  
Edit `/etc/ansible/hosts` to add your cluster nodes:
```ini
[master]
node1 ansible_host=192.168.1.100
[worker]
node2 ansible_host=192.168.1.101
node3 ansible_host=192.168.1.102
```
✔️ Run a test command:
```bash
ansible all -m ping
```

---

## **6. Firewall & Security Hardening**
**partially exposed via DuckDNS**, harden security:
```bash
sudo apt install ufw fail2ban
sudo ufw default deny incoming
sudo ufw allow ssh
sudo ufw enable
sudo systemctl enable fail2ban
```
✔️ Set Fail2Ban rules to **prevent brute-force attacks**.

---

## **7. setup ngrok public tunnel**
on worker node
```
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
  | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
  && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
  | sudo tee /etc/apt/sources.list.d/ngrok.list \
  && sudo apt update \
  && sudo apt install ngrok
```
