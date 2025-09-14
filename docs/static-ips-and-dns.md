# VMStation Static IP Assignment and DNS Subdomains

This document describes the static IP assignments for critical Kubernetes components and the DNS subdomain configuration for the homelab.

## Overview

VMStation implements static IP assignments to ensure reliable communication between Kubernetes components and provides DNS subdomains for easy access to services. This addresses the problem statement requirements for:

1. **Static IP assignments for critical pods**: CoreDNS, kube-proxy, and kube-flannel
2. **DNS subdomain setup**: `homelab.com` domain with service-specific subdomains

## Static IP Assignments

### CoreDNS
- **Type**: Service ClusterIP
- **IP**: `10.96.0.10`
- **Configuration**: `/manifests/network/coredns-service.yaml`
- **Purpose**: Provides stable DNS service IP for cluster operations
- **Persistence**: Configured via Service definition with explicit `clusterIP`

### kube-proxy Pods
- **Type**: hostNetwork (uses node IP)
- **IPs**: 
  - Control plane (masternode): `192.168.4.63`
  - Storage node (storagenodet3500): `192.168.4.61`
  - Compute node (homelab): `192.168.4.62`
- **Configuration**: `/manifests/network/kube-proxy-daemonset.yaml`
- **Purpose**: Provides stable network proxy on each node
- **Persistence**: Uses `hostNetwork: true` to bind to static node IPs

### kube-flannel Pods
- **Type**: hostNetwork (uses node IP)
- **IPs**:
  - Control plane (masternode): `192.168.4.63`
  - Storage node (storagenodet3500): `192.168.4.61`
  - Compute node (homelab): `192.168.4.62`
- **Configuration**: `/manifests/cni/flannel.yaml`
- **Purpose**: Provides stable CNI networking on each node
- **Persistence**: Uses `hostNetwork: true` to bind to static node IPs

## DNS Subdomains (homelab.com)

### Configured Subdomains

| Subdomain | Target IP | Purpose | Port |
|-----------|-----------|---------|------|
| `jellyfin.homelab.com` | `192.168.4.61` | Jellyfin media server | 30096 |
| `grafana.homelab.com` | `192.168.4.63` | Grafana monitoring | TBD |
| `storage.homelab.com` | `192.168.4.61` | Storage node services | Various |
| `compute.homelab.com` | `192.168.4.62` | Compute node services | Various |
| `control.homelab.com` | `192.168.4.63` | Control plane services | Various |

### DNS Configuration Methods

The implementation provides multiple DNS resolution paths:

1. **CoreDNS Integration**: Modified CoreDNS ConfigMap to handle `homelab.com` domains
2. **External DNS Service**: Optional dnsmasq service for network-wide resolution
3. **Hosts File Backup**: Local hosts file entries as fallback

#### CoreDNS Configuration
- **File**: `/manifests/network/coredns-configmap.yaml`
- **Method**: Added dedicated `homelab.com:53` block with static host mappings
- **Scope**: Available to all pods and nodes in the cluster

#### External DNS Service (Optional)
- **Service**: `vmstation-dns.service` (systemd)
- **Configuration**: `/etc/vmstation/dns/homelab-subdomains.conf`
- **Method**: dnsmasq daemon for network-wide DNS resolution
- **Scope**: Available to all devices on the 192.168.4.0/24 network

## Usage Examples

### Access Services via Subdomains

```bash
# Access Jellyfin via subdomain
curl http://jellyfin.homelab.com:30096/

# Test from any device on the network
ping jellyfin.homelab.com

# Browse to Jellyfin in web browser
http://jellyfin.homelab.com:30096
```

### Test DNS Resolution

```bash
# Test subdomain resolution
nslookup jellyfin.homelab.com
nslookup grafana.homelab.com

# Test from within the cluster
kubectl run test-dns --image=busybox --rm -it -- nslookup jellyfin.homelab.com
```

## Installation and Setup

### Automatic Setup (Recommended)

The static IP and DNS configuration is automatically applied during cluster deployment:

```bash
# Full cluster deployment (includes static IP and DNS setup)
./deploy-cluster.sh deploy

# Or run the setup script manually
sudo ./scripts/setup_static_ips_and_dns.sh
```

### Manual Verification

```bash
# Verify static IP assignments and DNS configuration
./scripts/validate_static_ips_and_dns.sh

# Verify specific components only
./scripts/validate_static_ips_and_dns.sh static-ips
./scripts/validate_static_ips_and_dns.sh dns
```

### Network Configuration for Clients

To use the homelab.com subdomains from devices on your network:

1. **Router DNS Configuration** (Recommended):
   - Configure your router to use `192.168.4.63` as DNS server for `homelab.com` domain
   - Or set `192.168.4.63` as the primary DNS server

2. **Device-Specific Configuration**:
   - Add `192.168.4.63` as DNS server in network settings
   - Or add entries to local hosts file

## Maintenance

### Verify Static IPs

```bash
# Check all static IP assignments
sudo ./scripts/setup_static_ips_and_dns.sh --verify

# Check specific components
kubectl get service kube-dns -n kube-system -o yaml | grep clusterIP
kubectl get pods -n kube-system -l k8s-app=kube-proxy -o wide
kubectl get pods -n kube-flannel -l app=flannel -o wide
```

### Update DNS Configuration

#### Update CoreDNS (Preferred Method)
```bash
# Edit the CoreDNS ConfigMap
kubectl edit configmap coredns -n kube-system

# Restart CoreDNS pods to apply changes
kubectl rollout restart deployment coredns -n kube-system
```

#### Update External DNS Service
```bash
# Edit dnsmasq configuration
sudo nano /etc/vmstation/dns/homelab-subdomains.conf

# Restart the service
sudo systemctl restart vmstation-dns
```

### Add New Subdomains

1. **For new services**, add entries to CoreDNS ConfigMap:
   ```yaml
   hosts {
       192.168.4.61 jellyfin.homelab.com storage.homelab.com
       192.168.4.62 compute.homelab.com
       192.168.4.63 grafana.homelab.com control.homelab.com newservice.homelab.com
       fallthrough
   }
   ```

2. **Restart CoreDNS** to apply changes:
   ```bash
   kubectl rollout restart deployment coredns -n kube-system
   ```

### Troubleshooting

#### Static IP Issues
```bash
# Check pod status and IPs
kubectl get pods -o wide --all-namespaces

# Verify hostNetwork configuration
kubectl get daemonset kube-proxy -n kube-system -o yaml | grep hostNetwork
kubectl get daemonset kube-flannel-ds -n kube-flannel -o yaml | grep hostNetwork

# Check service configuration
kubectl get service kube-dns -n kube-system -o yaml
```

#### DNS Resolution Issues
```bash
# Test DNS resolution from control plane
nslookup jellyfin.homelab.com
dig jellyfin.homelab.com

# Test from within cluster
kubectl run test-dns --image=busybox --rm -it -- nslookup jellyfin.homelab.com

# Check CoreDNS status
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Check external DNS service (if used)
sudo systemctl status vmstation-dns
sudo journalctl -u vmstation-dns
```

#### Service Access Issues
```bash
# Test service accessibility
curl -v http://jellyfin.homelab.com:30096/
telnet jellyfin.homelab.com 30096

# Check service and endpoints
kubectl get service -n jellyfin
kubectl get endpoints -n jellyfin

# Check iptables rules for NodePort
sudo iptables -t nat -L | grep 30096
```

## Architecture Notes

### Why These Static IP Methods Work

1. **CoreDNS Service**: Uses Kubernetes Service with explicit `clusterIP`, ensuring the DNS service is always accessible at `10.96.0.10`

2. **hostNetwork Pods**: kube-proxy and kube-flannel use `hostNetwork: true`, which:
   - Binds pods directly to the host's network interface
   - Uses the node's IP address (which is static in VMStation)
   - Survives pod restarts since the node IP doesn't change

3. **DNS Subdomains**: Multiple resolution methods ensure reliability:
   - CoreDNS handles cluster-internal resolution
   - External DNS service provides network-wide resolution
   - Hosts file provides local fallback

### Compatibility

This configuration is compatible with:
- ✅ Existing VMStation deployment scripts
- ✅ CNI networking (Flannel)
- ✅ Service mesh implementations
- ✅ Ingress controllers
- ✅ External load balancers

### Limitations

- **Node IP Changes**: If node IPs change, kube-proxy and kube-flannel IPs will change accordingly
- **DNS Propagation**: External devices need DNS configuration to resolve homelab.com domains
- **Service Discovery**: Only covers predefined subdomains, not dynamic service discovery

## Security Considerations

- DNS service uses unprivileged user (`nobody`)
- No additional network ports exposed beyond standard Kubernetes
- CoreDNS modifications are minimal and don't affect cluster DNS
- External DNS service is optional and can be disabled

## Integration Points

This configuration integrates with existing VMStation components:

- **Deployment Scripts**: Automatically applied during `deploy-cluster.sh`
- **Fix Scripts**: Compatible with existing network fix procedures
- **Monitoring**: Works with Grafana and Prometheus deployments
- **Services**: Compatible with existing NodePort and LoadBalancer services

For questions or issues, refer to the validation script output or check the logs of the relevant services.