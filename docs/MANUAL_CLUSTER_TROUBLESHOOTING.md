# Manual Kubernetes Cluster Setup Troubleshooting

This guide addresses common issues encountered when manually setting up Kubernetes clusters, particularly the crictl and kubelet configuration problems mentioned in the deploy.sh error scenarios.

## Common Issues

### 1. crictl Connection Failures

**Symptoms:**
```bash
$ sudo crictl ps -a
WARN[0000] runtime connect using default endpoints: [unix:///var/run/dockershim.sock unix:///run/containerd/containerd.sock unix:///run/crio/crio.sock unix:///var/run/cri-dockerd.sock]. As the default settings are now deprecated, you should set the endpoint instead.
ERRO[0000] validate service connection: validate CRI v1 runtime API for endpoint "unix:///var/run/dockershim.sock": rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial unix /var/run/dockershim.sock: connect: no such file or directory"
```

**Root Cause:** 
crictl is trying to use deprecated dockershim endpoints instead of the proper containerd endpoint.

**Fix:**
```bash
sudo ./scripts/fix_manual_cluster_setup.sh
```

### 2. Kubelet in Standalone Mode

**Symptoms:**
```bash
$ sudo journalctl -u kubelet -xe
Sep 09 14:37:19 masternode kubelet[3098388]: I0909 14:37:19.274583 3098388 server.go:655] "Standalone mode, no API client"
Sep 09 14:37:19 masternode kubelet[3098388]: I0909 14:37:19.281165 3098388 server.go:543] "No api server defined - no events will be sent to API server"
```

**Root Cause:**
kubelet is not properly configured to connect to the Kubernetes API server.

**Fix:**
```bash
sudo ./scripts/fix_kubelet_cluster_connection.sh
```

### 3. Container Runtime Issues

**Symptoms:**
```bash
ERRO[0000] validate service connection: validate CRI v1 image API for endpoint "unix:///var/run/dockershim.sock": rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial unix /var/run/dockershim.sock: connect: no such file or directory"
```

**Root Cause:**
containerd service is not running or properly configured.

**Fix:**
```bash
sudo ./scripts/fix_manual_cluster_setup.sh
```

## Automated Deployment

For automated deployment without manual intervention:

```bash
# Deploy complete cluster
./deploy.sh cluster

# Deploy only applications (requires existing cluster)
./deploy.sh apps

# Check deployment status
./deploy.sh check
```

## Manual Troubleshooting Steps

### Step 1: Verify Container Runtime
```bash
# Check containerd service
sudo systemctl status containerd

# If not running, start it
sudo systemctl enable containerd
sudo systemctl start containerd

# Test container runtime
sudo crictl version
```

### Step 2: Configure crictl
```bash
# Create crictl configuration
sudo tee /etc/crictl.yaml << 'EOF'
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# Test crictl
sudo crictl ps -a
```

### Step 3: Check Kubelet Configuration
```bash
# Check if node is joined to cluster
ls -la /etc/kubernetes/kubelet.conf

# Check kubelet service
sudo systemctl status kubelet

# View recent kubelet logs
sudo journalctl -u kubelet -f
```

### Step 4: Node Join Status

**Master Node:**
- Should have `/etc/kubernetes/admin.conf`
- Should be able to run `kubectl get nodes`

**Worker Node:**
- Should have `/etc/kubernetes/kubelet.conf` after joining
- Should show in `kubectl get nodes` from master

## Detailed Diagnostics

### Container Runtime Diagnostics
```bash
# Check containerd socket
ls -la /var/run/containerd/containerd.sock

# Test containerd directly
sudo ctr version

# Check containerd configuration
sudo cat /etc/containerd/config.toml | head -20
```

### Kubelet Diagnostics
```bash
# Check kubelet systemd configuration
sudo cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Check kubelet cluster configuration (if joined)
sudo cat /etc/kubernetes/kubelet.conf | head -10

# Check kubelet logs for errors
sudo journalctl -u kubelet --no-pager -n 50 | grep -E "(ERROR|WARN|Failed)"
```

### Network Connectivity (Worker to Master)
```bash
# Test connectivity to master API server
curl -k https://192.168.4.63:6443/healthz

# Check if firewall is blocking
sudo firewall-cmd --list-all

# Test DNS resolution
nslookup kubernetes.default.svc.cluster.local
```

## Fix Scripts Usage

### General Manual Setup Issues
```bash
# Run comprehensive manual setup fix
sudo ./scripts/fix_manual_cluster_setup.sh

# This script:
# - Configures crictl for containerd
# - Verifies and starts containerd service
# - Checks kubelet configuration
# - Provides diagnostic information
```

### Kubelet Standalone Mode Issues
```bash
# Run kubelet cluster connection fix
sudo ./scripts/fix_kubelet_cluster_connection.sh

# This script:
# - Detects standalone vs cluster mode
# - Fixes kubelet systemd configuration
# - Handles pre-join vs post-join scenarios
# - Provides cluster join guidance
```

## Prevention

### Use Enhanced Deployment
The VMStation deployment system includes RHEL 10+ compatibility fixes:

```bash
# Run RHEL 10 specific pre-setup (if needed)
ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/rhel10_setup_fixes.yaml

# Then run normal cluster setup
./deploy.sh cluster
```

### Regular Health Checks
```bash
# Validate cluster health
./scripts/validate_k8s_monitoring.sh

# Check node status
kubectl get nodes -o wide

# Check system services
sudo systemctl status kubelet containerd
```

## Expected Results After Fixes

### Working crictl:
```bash
$ sudo crictl ps -a
CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID              POD
<containers listed without warnings>
```

### Working kubelet (cluster mode):
```bash
$ sudo journalctl -u kubelet -n 5
Sep 09 15:00:00 node kubelet[12345]: I0909 15:00:00.123456 12345 kubelet.go:xxx] "Successfully registered node"
Sep 09 15:00:00 node kubelet[12345]: I0909 15:00:00.123456 12345 kubelet.go:xxx] "Node ready"
```

### Working cluster connection:
```bash
$ kubectl get nodes
NAME         STATUS   ROLES           AGE   VERSION
masternode   Ready    control-plane   1h    v1.29.15
workernode   Ready    <none>          1h    v1.29.15
```

## Support

If issues persist after running the fix scripts:

1. Check the [RHEL 10 Troubleshooting Guide](RHEL10_TROUBLESHOOTING.md) for OS-specific issues
2. Verify network connectivity between nodes
3. Ensure all required ports are open in firewall
4. Check system resources (disk space, memory)
5. Review the full deployment logs for additional context

For automated deployment, prefer using `./deploy.sh cluster` which includes all necessary fixes and configurations.