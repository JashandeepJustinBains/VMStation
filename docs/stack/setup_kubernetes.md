# Kubernetes Setup Guide

VMStation now uses Kubernetes as the primary infrastructure platform, replacing the previous Podman-based setup.

## Overview

The VMStation Kubernetes cluster uses:
- **Control Plane**: monitoring_nodes (192.168.4.63) - Acts as Kubernetes master
- **Worker Nodes**: storage_nodes (192.168.4.61) and compute_nodes (192.168.4.62)
- **Container Runtime**: containerd
- **CNI**: Flannel for pod networking
- **Certificate Management**: cert-manager for TLS certificates
- **Package Management**: Helm for application deployment

## Quick Start

### 1. Deploy Kubernetes Cluster
```bash
# Clone the repository
git clone https://github.com/JashandeepJustinBains/VMStation.git
cd VMStation

# Configure variables (edit as needed)
cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml

# Deploy the entire Kubernetes stack
./deploy_kubernetes.sh
```

### 2. Verify Deployment
```bash
# Validate the monitoring stack
./scripts/validate_k8s_monitoring.sh

# Check cluster status
kubectl get nodes -o wide
kubectl get pods -n monitoring
```

## Architecture

### Cluster Components
- **kubeadm**: Cluster initialization and management
- **containerd**: Container runtime
- **Flannel**: Pod network (CIDR: 10.244.0.0/16)
- **cert-manager**: TLS certificate management
- **Helm**: Package management

### Monitoring Stack
- **Prometheus**: Metrics collection and alerting (NodePort: 30090)
- **Grafana**: Visualization and dashboards (NodePort: 30300)
- **Loki**: Log aggregation and querying (NodePort: 31100)
- **AlertManager**: Alert routing and management (NodePort: 30903)
- **Node Exporter**: Host metrics collection
- **Promtail**: Log collection agent

## Manual Setup Steps

### 1. Install Kubernetes
```bash
# Run the cluster setup playbook
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cluster.yaml
```

### 2. Install Helm
```bash
# Install Helm and add repositories
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_helm.yaml
```

### 3. Setup Certificate Management
```bash
# Install cert-manager and create CA
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/setup_cert_manager.yaml
```

### 4. Deploy Monitoring Stack
```bash
# Deploy Prometheus, Grafana, and Loki using Helm
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_monitoring.yaml
```

## Access URLs

After deployment, access the monitoring services via NodePort:

- **Grafana**: http://192.168.4.63:30300 (admin/admin)
- **Prometheus**: http://192.168.4.63:30090
- **Loki**: http://192.168.4.63:31100
- **AlertManager**: http://192.168.4.63:30903

## Common Operations

### Cluster Management
```bash
# View cluster status
kubectl get nodes
kubectl cluster-info

# Check system pods
kubectl get pods -n kube-system

# View monitoring stack
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

### Application Management
```bash
# List Helm releases
helm list -n monitoring

# Upgrade monitoring stack
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring

# Scale deployments
kubectl scale deployment grafana -n monitoring --replicas=2
```

### Certificate Management
```bash
# View certificates
kubectl get certificates -n monitoring
kubectl get clusterissuers

# Check certificate status
kubectl describe certificate grafana-tls -n monitoring
```

### Troubleshooting
```bash
# View pod logs
kubectl logs -n monitoring deployment/grafana

# Debug pod issues
kubectl describe pod <pod-name> -n monitoring

# Check service endpoints
kubectl get endpoints -n monitoring

# Port forward for debugging
kubectl port-forward -n monitoring svc/grafana 3000:80
```

## Storage

The cluster uses local-path storage class for persistent volumes:
- **Prometheus data**: 10Gi
- **Grafana data**: 5Gi  
- **Loki data**: 10Gi
- **AlertManager data**: 2Gi

## Security

### TLS Certificates
- Self-signed CA created for internal communications
- Individual certificates issued for each service
- cert-manager handles certificate lifecycle

### Network Policies
Network policies can be implemented to restrict traffic between namespaces and pods.

### RBAC
Role-Based Access Control is configured for service accounts and monitoring components.

## Migration from Podman

The Kubernetes setup replaces the previous Podman-based infrastructure:

### What Changed
- Container orchestration moved from Podman to Kubernetes
- Monitoring stack deployed using Helm charts instead of individual containers
- TLS certificate management added with cert-manager
- Persistent storage managed by Kubernetes PVCs
- Service discovery through Kubernetes DNS

### Backward Compatibility
- Existing SSH key setup between nodes is preserved
- Same monitoring services (Prometheus, Grafana, Loki) with enhanced features
- Configuration variables maintained in group_vars for easy migration

## Advanced Configuration

### Custom Storage Classes
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ssd-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
```

### Ingress Setup
```bash
# Install ingress controller
helm install ingress-nginx ingress-nginx/ingress-nginx

# Create ingress for monitoring services
kubectl apply -f k8s/ingress/monitoring-ingress.yaml
```

### External Access
For external access to monitoring services, consider:
1. **NodePort**: Direct access via node IP and port (current setup)
2. **LoadBalancer**: Cloud provider load balancer
3. **Ingress**: HTTP/HTTPS routing with domain names
4. **Port Forwarding**: kubectl port-forward for temporary access

## Best Practices

1. **Resource Limits**: Set resource requests and limits for all pods
2. **Monitoring**: Use the deployed Prometheus to monitor cluster health
3. **Backups**: Regular backup of persistent volumes and cluster state
4. **Updates**: Keep Kubernetes and applications updated
5. **Security**: Regular security scanning and vulnerability assessment
