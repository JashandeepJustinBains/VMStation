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
set up **distributed cluster with MPI, Grafana, Prometheus, Ansible, Jenkins, and more**

---

## **1. Base System Setup**
Before installing services, ensure you have:
✅ **Debian Linux (Headless) installed on each node**  
✅ **Static IP addresses configured for each machine**  
✅ **SSH access enabled across all nodes**  

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install ssh net-tools htop tmux git curl wget
```
✔️ These packages provide basic system utilities for management.

---

## **2. MPI (Message Passing Interface)**
MPI enables **distributed computing across nodes**.

### **Install OpenMPI (Recommended)**
```bash
sudo apt install openmpi-bin openmpi-common libopenmpi-dev
```
- **Test with a simple MPI script:**  
```bash
mpiexec -n 4 hostname
```
✔️ This runs a test across four MPI processes.

---

## **3. Monitoring: Grafana + Prometheus**
Grafana + Prometheus tracks **system performance metrics**.

### **Install Prometheus**
```bash
sudo apt install prometheus prometheus-node-exporter
```
### **Install Grafana**
```bash
sudo apt install grafana
sudo systemctl enable grafana-server
sudo systemctl start grafana-server
```
✔️ You’ll configure dashboards in Grafana to visualize **CPU/RAM usage**.

---

## **4. Orchestration: Ansible**
Ansible automates **configuration & deployment** across your cluster.

### **Install Ansible**
```bash
sudo apt install ansible
```
✔️ **Define inventory:**  
Edit `/etc/ansible/hosts` to add your cluster nodes:
```ini
[cluster]
node1 ansible_host=192.168.1.100
node2 ansible_host=192.168.1.101
node3 ansible_host=192.168.1.102
```
✔️ Run a test command:
```bash
ansible all -m ping
```

---

## **5. CI/CD Pipeline: Jenkins**
Jenkins automates code compilation and deployment.

### **Install Jenkins**
```bash
sudo apt install openjdk-11-jdk
wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io.key | sudo apt-key add -
sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
sudo apt update
sudo apt install jenkins
```
✔️ **Start Jenkins**
```bash
sudo systemctl start jenkins
```
✔️ **Set Up Jenkins Pipeline**
- Configure a **GitHub Webhook** for automated build triggers.
- Define tasks in `Jenkinsfile` to compile and distribute workloads.

---

## **6. Firewall & Security Hardening**
Since your cluster is **partially exposed via DuckDNS**, harden security:
```bash
sudo apt install ufw fail2ban
sudo ufw default deny incoming
sudo ufw allow ssh
sudo ufw enable
sudo systemctl enable fail2ban
```
✔️ Set Fail2Ban rules to **prevent brute-force attacks**.

---

## **7. System Metrics & Benchmarking**
Ensure efficient resource usage:
✅ **Install `htop` and `dstat` to monitor system performance**  
✅ **Use `mpstat` to analyze MPI workload distribution**  
✅ **Enable logging for debugging task execution**  

```bash
sudo apt install htop dstat sysstat
```

