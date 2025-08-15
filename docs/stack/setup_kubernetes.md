# Kubernetes Setup Guide

## Install Kubernetes (k8s)
- Use kubeadm or MicroK8s for cluster setup
- Configure networking, storage, and ingress

## Example Commands
```bash
sudo apt update && sudo apt install kubeadm -y
sudo kubeadm init
kubectl get nodes
```

## Tips
- Use static IPs for all nodes
- Monitor resource usage
