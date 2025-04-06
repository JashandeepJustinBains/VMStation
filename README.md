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


