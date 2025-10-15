# DNS, Syslog & Kerberos Status Report

**Date:** 2025-10-14 23:10 EDT

---

## ✅ DNS ISSUE - FIXED

### Problem
Grafana couldn't resolve Prometheus/Loki service names:
- Error: `dial tcp: lookup prometheus.monitoring.svc.cluster.local: Try again`
- Root cause: CoreDNS was not deployed, nodelocaldns had conflicts

### Solution Applied
1. **Deployed CoreDNS** using Kubespray:
   ```bash
   cd /srv/monitoring_data/VMStation/.cache/kubespray
   ansible-playbook -i inventory/mycluster/inventory.ini cluster.yml -b --tags coredns
   ```

2. **Removed conflicting nodelocaldns:**
   ```bash
   kubectl delete daemonset nodelocaldns -n kube-system
   ```

3. **Updated kubelet DNS on all nodes:**
   ```bash
   # Changed from 169.254.25.10 (nodelocaldns) to 10.233.0.3 (coredns)
   sed -i 's/169\.254\.25\.10/10.233.0.3/g' /var/lib/kubelet/config.yaml
   systemctl restart kubelet
   ```

4. **Restarted Grafana** to pick up new DNS configuration

### Result
- ✅ CoreDNS running: `coredns-77f7cc69db-7h6qw` and `coredns-77f7cc69db-fmj98`
- ✅ DNS service: `coredns` at `10.233.0.3:53`
- ✅ Grafana can now resolve: `prometheus.monitoring.svc.cluster.local` → `10.233.117.8`
- ✅ Grafana health: `database: ok`
- ✅ Datasources configured correctly

### Verification
```bash
kubectl exec -n monitoring deployment/grafana -- nslookup prometheus.monitoring.svc.cluster.local
# Server:    10.233.0.3
# Address:   10.233.0.3:53
# Name:      prometheus.monitoring.svc.cluster.local
# Address:   10.233.117.8
```

---

## ⚠️ SYSLOG - NOT CONFIGURED

### Current Status
**No syslog collection currently active**

### What's Missing
1. **Syslog receiver** - No syslog server pod deployed
2. **Syslog forwarding** - Nodes not configured to forward syslogs
3. **Syslog dashboard** - JSON parse error (malformed)

### Syslog Dashboard Error
```
logger=provisioning.dashboard type=file name=default
error="invalid character '{' looking for beginning of object key string"
file=/var/lib/grafana/dashboards/syslog-dashboard.json
```

### To Deploy Syslog Collection

**Option 1: Promtail (Already Running)**
Promtail is already deployed as a DaemonSet and can collect syslogs.
Configure promtail to scrape `/var/log/syslog`:

```yaml
# Add to promtail config
- job_name: syslog
  static_configs:
    - targets:
        - localhost
      labels:
        job: syslog
        __path__: /var/log/syslog
```

**Option 2: Dedicated Syslog Server**
Deploy rsyslog or syslog-ng as a service:
- Receive syslogs on port 514 (UDP/TCP)
- Forward to Loki via promtail
- Store logs in `/srv/monitoring_data/syslog/`

**Option 3: Fluent Bit**
Deploy Fluent Bit DaemonSet:
- Collect system logs
- Forward to Loki
- More efficient than promtail for syslog

### Recommended Action
```bash
# Fix syslog dashboard JSON
kubectl edit configmap grafana-dashboards -n monitoring
# Find and fix the malformed JSON in syslog-dashboard.json

# Configure promtail for syslog collection
kubectl edit configmap promtail-config -n monitoring
# Add syslog scrape config
```

---

## ⚠️ KERBEROS/FreeIPA - NOT DEPLOYED

### Current Status
**No Kerberos/FreeIPA infrastructure deployed**

### What's Needed for Kerberos

**FreeIPA Server Components:**
1. **LDAP** - User directory
2. **Kerberos KDC** - Key Distribution Center
3. **DNS** - (Already have CoreDNS ✓)
4. **NTP** - (Already have Chrony ✓)
5. **CA** - Certificate Authority

**Deployment Options:**

**Option 1: FreeIPA in Kubernetes**
```bash
# Deploy FreeIPA server pod
kubectl apply -f freeipa-deployment.yaml

# Initialize FreeIPA
ipa-server-install --realm=VMSTATION.LOCAL \
  --domain=vmstation.local \
  --setup-dns --no-forwarders
```

**Option 2: External FreeIPA Server**
- Deploy FreeIPA on a separate VM/host
- Configure Kubernetes nodes as IPA clients
- Use for SSO and authentication

**Option 3: Simple Kerberos (without FreeIPA)**
```bash
# Deploy standalone MIT Kerberos KDC
# Lighter weight, but fewer features
```

### Infrastructure Deployment Manifest Location
Check: `/srv/monitoring_data/VMStation/ansible/playbooks/deploy-infrastructure-services.yaml`

The infrastructure playbook includes FreeIPA but it wasn't deployed. Check logs:
```bash
cat /srv/monitoring_data/VMStation/ansible/artifacts/deploy-infrastructure-services.log | grep -i "freeipa\|kerberos"
```

### Recommended Next Steps for Kerberos

1. **Decide on scope:**
   - Just Kubernetes auth? (Use OIDC instead)
   - Full enterprise auth? (Deploy FreeIPA)
   - Service-to-service auth? (Use service mesh + mTLS)

2. **If deploying FreeIPA:**
   ```bash
   # Create FreeIPA deployment
   # Will need:
   # - Persistent storage (already have local-path ✓)
   # - Privileged container (for systemd)
   # - Hostnetwork access
   # - Static IP or LoadBalancer
   ```

3. **Alternative - OIDC Integration:**
   ```bash
   # Use external identity provider (Keycloak, Dex, etc.)
   # Configure kube-apiserver for OIDC
   # Simpler than full Kerberos
   ```

---

## CURRENT CLUSTER STATUS

### ✅ Working Components
- **Kubernetes cluster:** 3 nodes operational
- **DNS:** CoreDNS working (10.233.0.3)
- **Monitoring:** Prometheus, Loki, Grafana all accessible
- **Storage:** Local-path provisioner on masternode
- **NTP:** Chrony running on all nodes
- **Networking:** Calico CNI operational

### ⚠️ Pending Components
- **Syslog collection:** Not configured
- **Kerberos/FreeIPA:** Not deployed
- **Grafana syslog dashboard:** JSON error

### 🌐 Service Access
- Grafana: http://192.168.4.63:30300 ✅
- Prometheus: http://192.168.4.63:30090 ✅
- Loki: http://192.168.4.63:31100 ✅

---

## IMMEDIATE ACTIONS REQUIRED

### 1. Fix Syslog Dashboard
```bash
kubectl get configmap grafana-dashboards -n monitoring -o yaml > /tmp/dashboards.yaml
# Edit and fix JSON syntax error
kubectl apply -f /tmp/dashboards.yaml
kubectl rollout restart deployment/grafana -n monitoring
```

### 2. Enable Syslog Collection (Choose One)

**Quick Fix - Promtail:**
```bash
kubectl edit configmap promtail-config -n monitoring
# Add syslog job to scrape /var/log/syslog
kubectl rollout restart daemonset/promtail -n monitoring
```

**Full Solution - Dedicated Syslog Server:**
```bash
# Deploy rsyslog server
kubectl apply -f /srv/monitoring_data/syslog-server.yaml
# Configure nodes to forward to rsyslog
```

### 3. Kerberos Decision
- **Option A:** Skip Kerberos, use OIDC/OAuth for auth
- **Option B:** Deploy FreeIPA for full enterprise identity management
- **Option C:** Deploy lightweight Kerberos KDC only

---

## FILES TO UPDATE

1. **Syslog Dashboard:** Fix JSON in grafana-dashboards ConfigMap
2. **Promtail Config:** Add syslog scrape job
3. **Infrastructure Playbook:** Enable FreeIPA deployment (if needed)

## VALIDATION COMMANDS

```bash
# Check DNS
kubectl exec -n monitoring deployment/grafana -- nslookup prometheus.monitoring.svc.cluster.local

# Check Grafana datasources
curl -s http://192.168.4.63:30300/api/datasources | jq

# Check syslog collection (after configured)
kubectl logs -n monitoring -l app=promtail | grep syslog

# Check Kerberos (after deployed)
kubectl get pods -n infrastructure | grep -i freeipa
```

---

**Summary:** DNS is now fixed and Grafana can connect to Prometheus/Loki. Syslog and Kerberos require configuration decisions and deployment.
