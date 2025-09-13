# VMStation Kubernetes DNS Fix Guide

## Problem Statement
When running `kubectl version --short`, you get the error:
```
Unable to connect to the server: dial tcp: lookup hort on 192.168.4.1:53: no such host
```

This indicates your Kubernetes cluster is configured to use the router gateway (192.168.4.1) for DNS resolution instead of the cluster's CoreDNS service.

## Root Cause
The issue occurs when:
1. Nodes are configured to use router DNS (192.168.4.1) instead of cluster DNS
2. kubelet is not properly configured to use CoreDNS for cluster operations
3. systemd-resolved or /etc/resolv.conf prioritizes router DNS over cluster DNS

## Solution

### Step 1: Apply the DNS Fix
Run the DNS configuration fix script on the control plane node:

```bash
sudo ./scripts/fix_cluster_dns_configuration.sh
```

**What this script does:**
- Configures kubelet to use CoreDNS (typically 10.96.0.10) for cluster DNS
- Updates systemd-resolved to handle .cluster.local domains properly
- Modifies /etc/resolv.conf to prioritize cluster DNS for Kubernetes operations
- Restarts kubelet service to apply changes
- Tests that the fix works

### Step 2: Validate the Fix
Run the validation test:

```bash
sudo ./scripts/test_dns_fix.sh
```

**Expected results after fix:**
- ✅ `kubectl version --client` works without errors
- ✅ `kubectl get nodes` shows cluster nodes
- ✅ CoreDNS pods are running
- ✅ Cluster DNS resolution works for internal services

### Step 3: Integrate into Deployment (Optional)
The DNS fix is automatically included in the deployment process:

```bash
./deploy-cluster.sh deploy
```

The script `fix_cluster_dns_configuration.sh` is now run as part of post-deployment fixes.

## Troubleshooting

### If the fix doesn't work:

1. **Check kubelet logs:**
   ```bash
   journalctl -u kubelet -f
   ```

2. **Check CoreDNS status:**
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   kubectl logs -n kube-system -l k8s-app=kube-dns
   ```

3. **Test DNS directly:**
   ```bash
   nslookup kubernetes.default.svc.cluster.local 10.96.0.10
   ```

4. **Check DNS configuration:**
   ```bash
   cat /etc/resolv.conf
   cat /etc/systemd/system/kubelet.service.d/20-dns-cluster.conf
   ```

### Manual Rollback
If you need to revert the changes:

1. **Restore original resolv.conf:**
   ```bash
   sudo cp /etc/resolv.conf.backup-vmstation /etc/resolv.conf
   ```

2. **Remove kubelet DNS configuration:**
   ```bash
   sudo rm -f /etc/systemd/system/kubelet.service.d/20-dns-cluster.conf
   sudo systemctl daemon-reload && sudo systemctl restart kubelet
   ```

3. **Remove systemd-resolved configuration:**
   ```bash
   sudo rm -f /etc/systemd/resolved.conf.d/cluster-dns.conf
   sudo systemctl restart systemd-resolved
   ```

## Technical Details

### DNS Configuration Applied

1. **Kubelet Configuration** (`/etc/systemd/system/kubelet.service.d/20-dns-cluster.conf`):
   ```
   [Service]
   Environment="KUBELET_DNS_ARGS=--cluster-dns=10.96.0.10 --cluster-domain=cluster.local"
   ```

2. **systemd-resolved Configuration** (`/etc/systemd/resolved.conf.d/cluster-dns.conf`):
   ```
   [Resolve]
   Domains=~cluster.local
   DNS=10.96.0.10
   FallbackDNS=192.168.4.1 8.8.8.8 8.8.4.4
   ```

3. **resolv.conf Update**:
   - CoreDNS (10.96.0.10) is set as the first nameserver
   - cluster.local is added to search domains
   - Router DNS (192.168.4.1) remains as fallback

### Files Modified
- `/etc/systemd/system/kubelet.service.d/20-dns-cluster.conf` (created)
- `/etc/systemd/resolved.conf.d/cluster-dns.conf` (created, if systemd-resolved is active)
- `/etc/resolv.conf` (modified, backup created at `/etc/resolv.conf.backup-vmstation`)

## Integration with VMStation

This fix is now integrated into the VMStation deployment process:
- Included in `deploy-cluster.sh` as part of post-deployment fixes
- Automatically runs after cluster bootstrap
- Can be run standalone for existing clusters

The fix ensures that kubectl and other Kubernetes components can properly resolve cluster services and communicate with the API server.