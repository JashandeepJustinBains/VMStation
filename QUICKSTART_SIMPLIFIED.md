# Quick Start Guide - Simplified Kubernetes Deployment

## Overview
This guide explains how to use the simplified Kubernetes deployment playbook. The deployment has been streamlined to complete in ~5-10 minutes instead of 15-20 minutes.

## Prerequisites
1. **Control Plane Node (masternode):**
   - Debian Bookworm
   - Root access
   - IP: 192.168.4.63

2. **Worker Node (storagenodet3500):**
   - Debian Bookworm  
   - Root access
   - IP: 192.168.4.61

3. **From masternode, SSH access to all nodes must work**

## Quick Deploy

### Option 1: Single Command Deploy
```bash
cd /home/runner/work/VMStation/VMStation
./deploy.sh debian
```

This will:
- Install Kubernetes binaries on all nodes
- Initialize control plane on masternode
- Deploy Flannel CNI
- Join worker nodes
- Validate cluster
- Deploy monitoring stack (Prometheus, Grafana)

### Option 2: Step-by-Step Deploy
```bash
# 1. Check syntax first
ansible-playbook --syntax-check ansible/playbooks/deploy-cluster.yaml

# 2. Deploy cluster
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/deploy-cluster.yaml

# 3. Verify deployment
kubectl get nodes
kubectl get pods -A
```

## Post-Deployment Verification

### 1. Verify kubectl works without login
```bash
# On masternode, as root
kubectl get nodes

# Should show both nodes as Ready without any authentication prompts
```

### 2. Verify crictl works
```bash
# On masternode
crictl ps

# Should list running containers including kube-apiserver, etcd, etc.
```

### 3. Check all pods are running
```bash
kubectl get pods -A

# All pods should be Running or Completed
```

### 4. Test DNS resolution
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Should resolve successfully
```

## What Changed?

### 1. kubectl Now Works Automatically
**Before:** Had to manually configure kubectl context and credentials  
**After:** kubectl automatically uses `/etc/kubernetes/admin.conf`

Just run:
```bash
kubectl get nodes -A
kubectl get pods -A
```

No login or password required!

### 2. crictl Configuration
**Before:** crictl would error with "connection refused"  
**After:** Properly configured with `/etc/crictl.yaml`

```bash
crictl ps       # List containers
crictl pods     # List pods
crictl images   # List images
```

### 3. Faster Deployment
**Before:** 15-20 minutes, often hung at Flannel deployment  
**After:** 5-10 minutes, reliable completion

### 4. Clearer Phase Structure
```
Phase 0: System Preparation (Install binaries, configure containerd, create directories)
Phase 1: Control Plane Initialization (kubeadm init)
Phase 2: Control Plane Validation (Verify API server)
Phase 3: Token Generation (Create join token)
Phase 4: CNI Deployment (Deploy Flannel before workers join)
Phase 5: Worker Node Join (Join workers to cluster)
Phase 6: Cluster Validation (Verify all nodes Ready)
Phase 7: Application Deployment (Deploy monitoring stack)
```

## Deployment Timeline

Typical deployment takes ~5-10 minutes:

- **Phase 0:** ~2 minutes (install binaries on 2 nodes)
- **Phase 1:** ~1 minute (kubeadm init)
- **Phase 2:** ~30 seconds (wait for API server)
- **Phase 3:** ~10 seconds (generate token)
- **Phase 4:** ~1-2 minutes (download & deploy CNI)
- **Phase 5:** ~1 minute (worker join)
- **Phase 6:** ~1 minute (wait for nodes Ready)
- **Phase 7:** ~2 minutes (deploy monitoring)

**Total:** ~8-10 minutes

## Troubleshooting

### Issue: "kubectl: command not found"
**Solution:** Kubernetes binaries not installed
```bash
# Re-run Phase 0
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/deploy-cluster.yaml --tags phase0
```

### Issue: "The connection to the server localhost:8080 was refused"
**Solution:** KUBECONFIG not set
```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
# Or re-run deployment to set it permanently
```

### Issue: "crictl: cannot connect to runtime"
**Solution:** crictl config missing
```bash
cat > /etc/crictl.yaml << EOF
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
EOF
```

### Issue: Worker node fails to join
**Solution:** Check token validity
```bash
# On masternode
kubeadm token list

# If expired, generate new token
kubeadm token create --print-join-command
```

### Issue: Flannel pods not starting
**Solution:** Check CNI plugins installed
```bash
ls -la /opt/cni/bin/
# Should show: bridge, flannel, host-local, loopback, portmap, etc.

# If missing, re-run Phase 4
```

## Reset and Redeploy

### Full Reset
```bash
./deploy.sh reset
```

This will:
- Delete all pods and namespaces
- Remove Kubernetes configuration
- Clean up CNI and network settings
- Stop kubelet and containerd

### Clean Redeploy
```bash
./deploy.sh reset
./deploy.sh debian
```

## Advanced Usage

### Deploy Only Specific Phases
```bash
# Phase 0 only (system prep)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/deploy-cluster.yaml --tags phase0

# Skip monitoring deployment
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/deploy-cluster.yaml --skip-tags monitoring
```

### Check Mode (Dry Run)
```bash
./deploy.sh debian --check
```

### Custom Variables
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/deploy-cluster.yaml \
  -e kubernetes_version=1.30 \
  -e pod_network_cidr=10.245.0.0/16
```

## Directory Structure

All required directories are now created automatically in Phase 0:

```
/opt/cni/bin/              # CNI plugins (bridge, flannel, etc.)
/etc/cni/net.d/            # CNI configuration
/var/lib/kubelet/          # Kubelet data
/etc/containerd/           # Containerd config
/etc/kubernetes/           # Kubernetes config
/root/.kube/               # kubectl config
```

## Files Modified by Deployment

```
/etc/kubernetes/admin.conf                  # Admin kubeconfig
/etc/kubernetes/kubelet.conf                # Kubelet config (workers only)
/etc/crictl.yaml                            # crictl config
/etc/environment                            # KUBECONFIG env var
/root/.bashrc                               # KUBECONFIG export
/etc/modules-load.d/kubernetes.conf         # Kernel modules
/etc/containerd/config.toml                 # Containerd config
/opt/cni/bin/*                              # CNI plugin binaries
/etc/cni/net.d/10-flannel.conflist         # Flannel CNI config
```

## Next Steps

After successful deployment:

1. **Access Grafana:** http://192.168.4.63:30000
2. **Access Prometheus:** http://192.168.4.63:30090
3. **Deploy additional workloads:**
   ```bash
   kubectl create namespace myapp
   kubectl apply -f myapp.yaml
   ```

4. **Add more worker nodes:**
   - Add to `ansible/inventory/hosts.yml`
   - Re-run deployment

5. **Monitor cluster:**
   ```bash
   kubectl top nodes
   kubectl top pods -A
   ```

## Support

For issues or questions:
1. Check logs: `ansible/artifacts/deploy-debian.log`
2. Review documentation: `PLAYBOOK_SIMPLIFICATION_SUMMARY.md`
3. Check playbook: `ansible/playbooks/deploy-cluster.yaml`
