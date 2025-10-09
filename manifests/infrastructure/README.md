# VMStation Infrastructure Services

## Overview

This directory contains Kubernetes manifests for core infrastructure services that support the VMStation cluster. These services provide essential functionality for enterprise operations including time synchronization, centralized logging, and identity management.

## Services

### 1. Chrony NTP Service (`chrony-ntp.yaml`)

**Purpose:** Cluster-wide time synchronization

**Type:** DaemonSet (runs on every node)

**Key Features:**
- Syncs to Google Public NTP and Cloudflare NTP
- Provides NTP service to all cluster nodes
- Exports metrics for Prometheus monitoring
- NetworkPolicy for secure time sync traffic

**Ports:**
- UDP/TCP 123: NTP service
- TCP 9123: Prometheus metrics

**Deployment:**
```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/deploy-ntp-service.yaml
```

**Validation:**
```bash
./tests/validate-time-sync.sh
```

**Why It's Critical:**
- Resolves log timestamp inconsistencies
- Prevents false inactivity detection
- Required for Kerberos authentication
- Enables reliable time-based automation

---

### 2. Syslog Server (`syslog-server.yaml`)

**Purpose:** Centralized syslog collection and forwarding

**Type:** StatefulSet (persistent log storage)

**Key Features:**
- Accepts syslog from external devices (routers, switches, servers)
- Forwards logs to Loki for centralized storage
- Local file backup for compliance
- Prometheus metrics for monitoring

**Ports:**
- UDP 30514: Syslog (traditional, NodePort)
- TCP 30515: Syslog (reliable, NodePort)
- TCP 30601: Syslog TLS (RFC5424, NodePort)
- TCP 9102: Prometheus metrics

**Deployment:**
```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/deploy-syslog-service.yaml
```

**Configuration:**
Configure devices to send syslog to:
- `192.168.4.63:30514` (UDP)
- `192.168.4.63:30515` (TCP, recommended)

**Testing:**
```bash
# From cluster nodes
logger -t vmstation-test "Test message"

# Check logs in Grafana
# Query: {job="syslog"}
```

---

### 3. FreeIPA/Kerberos (`freeipa-statefulset.yaml`)

**Purpose:** Enterprise identity management and SSO

**Type:** StatefulSet (persistent identity database)

**Key Features:**
- Kerberos KDC for authentication
- LDAP directory for user/group management
- Built-in DNS server
- Web UI for administration
- Certificate Authority (CA)

**Ports:**
- TCP/UDP 88: Kerberos
- TCP/UDP 464: Kerberos password
- TCP 389: LDAP
- TCP 636: LDAPS
- TCP 30443: Web UI (NodePort)
- TCP/UDP 53: DNS

**Deployment:**
```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/deploy-kerberos-service.yaml
```

**Access:**
- Web UI: `https://192.168.4.63:30443`
- Default realm: `VMSTATION.LOCAL`
- Default admin user: `admin`
- Default password: `ChangeMe123!` (CHANGE THIS!)

**Security Warning:**
This is a POC/Lab deployment. Before production use:
1. Change default passwords
2. Configure firewall rules
3. Enable audit logging
4. Set up backup automation
5. Review NetworkPolicy

---

## Namespace

All infrastructure services are deployed to the `infrastructure` namespace:

```bash
kubectl create namespace infrastructure
kubectl label namespace infrastructure name=infrastructure vmstation.io/component=infrastructure
```

## Prerequisites

- Kubernetes cluster running
- kubectl available on control plane
- Minimum 6GB RAM and 3 CPU cores available
- 30GB+ persistent storage

## Deployment Order

Recommended deployment order:

1. **NTP/Chrony** (deploy first - required for other services)
2. **Syslog Server** (depends on Loki in monitoring namespace)
3. **FreeIPA/Kerberos** (optional - requires accurate time sync)

### Quick Deploy All Services

```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/deploy-infrastructure-services.yaml
```

### Selective Deployment

```bash
# Deploy only NTP
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/deploy-infrastructure-services.yaml --tags ntp

# Deploy only Syslog
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/deploy-infrastructure-services.yaml --tags syslog

# Deploy only Kerberos
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/deploy-infrastructure-services.yaml --tags kerberos
```

## Verification

### Check All Infrastructure Pods

```bash
kubectl get pods -n infrastructure -o wide
```

Expected output:
```
NAME                     READY   STATUS    RESTARTS   AGE
chrony-ntp-xxxxx         2/2     Running   0          5m
chrony-ntp-yyyyy         2/2     Running   0          5m
chrony-ntp-zzzzz         2/2     Running   0          5m
syslog-server-0          2/2     Running   0          3m
freeipa-0                1/1     Running   0          10m
```

### Check Services

```bash
kubectl get svc -n infrastructure
```

### Check Storage

```bash
kubectl get pvc -n infrastructure
```

## Monitoring Integration

All infrastructure services expose Prometheus metrics:

- **Chrony:** `http://<pod-ip>:9123/metrics`
- **Syslog:** `http://<pod-ip>:9102/metrics`

Metrics are automatically scraped by Prometheus if deployed with the monitoring stack.

## Troubleshooting

See [TROUBLESHOOTING_GUIDE.md](../../docs/TROUBLESHOOTING_GUIDE.md) for detailed troubleshooting procedures.

### Quick Checks

```bash
# Check pod status
kubectl get pods -n infrastructure

# Check logs
kubectl logs -n infrastructure <pod-name>

# Describe pod for events
kubectl describe pod -n infrastructure <pod-name>

# Check resource usage
kubectl top pods -n infrastructure

# Check NetworkPolicy
kubectl get networkpolicy -n infrastructure
```

## Security

All services are secured with:

- **NetworkPolicy:** Explicit ingress/egress rules
- **RBAC:** Dedicated ServiceAccounts with minimal permissions
- **Security Contexts:** Non-root users, read-only filesystems
- **Resource Limits:** CPU/memory limits prevent resource exhaustion

## Backup and Recovery

### Syslog Server

Logs are stored in:
- Persistent volume: `/var/log/syslog-ng` (in pod)
- Also forwarded to Loki for centralized storage

Backup:
```bash
kubectl exec -n infrastructure syslog-server-0 -- tar czf /tmp/syslog-backup.tar.gz /var/log/syslog-ng
kubectl cp infrastructure/syslog-server-0:/tmp/syslog-backup.tar.gz ./syslog-backup.tar.gz
```

### FreeIPA

FreeIPA data is stored in persistent volume. Backup:

```bash
# Inside FreeIPA pod
kubectl exec -n infrastructure freeipa-0 -- ipa-backup

# Copy backup out
kubectl cp infrastructure/freeipa-0:/var/lib/ipa/backup/<backup-name> ./freeipa-backup/
```

## Documentation

- **Enterprise Implementation Summary:** `docs/ENTERPRISE_IMPLEMENTATION_SUMMARY.md`
- **Troubleshooting Guide:** `docs/TROUBLESHOOTING_GUIDE.md`
- **Deployment Playbooks:** `ansible/playbooks/deploy-*-service.yaml`
- **Validation Scripts:** `tests/validate-time-sync.sh`

## Related Services

Infrastructure services integrate with:

- **Monitoring Namespace:** Loki (log storage), Prometheus (metrics)
- **Kube-system Namespace:** CoreDNS (DNS resolution)

## Support

For issues or questions:

1. Check pod logs: `kubectl logs -n infrastructure <pod-name>`
2. Review troubleshooting guide: `docs/TROUBLESHOOTING_GUIDE.md`
3. Run validation scripts: `./tests/validate-time-sync.sh`
4. Check documentation in `docs/` directory

## License

Part of the VMStation project.
