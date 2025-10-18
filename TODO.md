# VMStation TODO List

## Current Workflow Commands

```bash
clear
git pull
./deploy.sh reset 
./deploy.sh setup
# ./deploy.sh debian         
# ./deploy.sh monitoring     
# ./deploy.sh infrastructure 
./deploy.sh kubespray
# validate monitoring stack and run full validation
./scripts/validate-monitoring-stack.sh
./tests/test-complete-validation.sh
```

```bash
./deploy.sh reset
# ./deploy.sh setup
# If using Kubespray path:
./scripts/run-kubespray.sh
# or legacy debian path (if applicable)
# ./deploy.sh debian

# Deploy monitoring and infra
./deploy.sh monitoring
./deploy.sh infrastructure

# Validate
./scripts/validate-monitoring-stack.sh
./tests/test-sleep-wake-cycle.sh
./tests/test-complete-validation.sh
```

## 🆕 New Features (January 2025)

### Kubespray Integration ✅

- [x] **Kubespray deployment path added** as alternative to RKE2 for RHEL10 nodes
  - Script: `scripts/run-kubespray.sh`
  - Preflight role: `ansible/roles/preflight-rhel10`
  - Playbook: `ansible/playbooks/run-preflight-rhel10.yml`
  
- [x] **Documentation consolidation** - Minimized repository surface area
  - New: `docs/ARCHITECTURE.md` (consolidated architecture documentation)
  - New: `docs/TROUBLESHOOTING.md` (consolidated troubleshooting guides)
  - New: `docs/USAGE.md` (comprehensive usage guide with kubespray)
  - New: `README.md` (project overview and quick start)
  - Old root docs preserved in `docs/` directory

### Usage

**Preflight checks for RHEL10**:
```bash
ansible-playbook -i ansible/inventory/hosts.yml \
  ansible/playbooks/run-preflight-rhel10.yml
```

**Stage Kubespray**:
```bash
./scripts/run-kubespray.sh
```

**Deploy with Kubespray** (follow on-screen instructions after staging)

## Immediate Issues - January 2025

### ✅ Fixed Issues
- [x] **CNI Plugin Installation** - Fixed loopback plugin missing on worker nodes (storagenodet3500)
  - Root cause: CNI plugins only installed on masternode
  - Solution: Moved installation to Phase 0 on all Debian nodes
  - Documentation: `docs/CNI_PLUGIN_FIX_JAN2025.md`

- [x] **Blackbox Exporter CrashLoopBackOff** - Fixed config parsing error (October 2025)
  - Root cause: `timeout` field incorrectly nested in DNS prober config
  - Solution: Moved `timeout` to module level in blackbox.yml ConfigMap
  - Documentation: `docs/BLACKBOX_EXPORTER_DIAGNOSTICS.md`

- [x] **Loki CrashLoopBackOff** - Fixed schema validation error (October 2025)
  - Root cause: boltdb-shipper requires 24h index period, but 168h was configured
  - Solution: Changed schema_config period from 168h to 24h
  - Documentation: `docs/MONITORING_STACK_FIXES_OCT2025.md`

- [x] **Jellyfin Pod Pending** - Fixed node scheduling issue (October 2025)
  - Root cause: storagenodet3500 node was marked unschedulable
  - Solution: Added automatic node uncordon task in ansible playbook
  - Documentation: `docs/MONITORING_STACK_FIXES_OCT2025.md`

- [x] **WoL Validation SSH Error** - Fixed homelab SSH authentication (October 2025)
  - Root cause: WoL task hardcoded root user instead of using ansible_user
  - Solution: Use `ansible_user` from inventory for SSH connections
  - Documentation: `docs/MONITORING_STACK_FIXES_OCT2025.md`

### 🔧 Monitoring & Observability

#### IPMI Hardware Monitoring
- [ ] Install IPMI exporter or IDrac exporter for hardware monitoring
  - Requires IPMI credentials for remote access
  - Target: homelab (RHEL10) node at 192.168.4.62
  - Expected metric endpoint: `http://192.168.4.62:9290`
  - Current status: Down (no credentials configured)
  - **Action:** Document IPMI credential requirements in manifests/monitoring/ipmi-exporter

#### Dashboard Issues (Enterprise-Grade Improvements Completed - Oct 2025)

**✅ COMPLETED:**
- [x] **Enhanced Loki Logs & Aggregation** dashboard to enterprise-grade
  - Added service health indicators (status, ingestion rate, error/warning rates)
  - Implemented template variables for namespace filtering
  - Added top log-producing pods table
  - Added Loki performance metrics panel
  - Enhanced log panels with better formatting
  - Documentation: `docs/GRAFANA_DASHBOARD_USAGE_GUIDE.md`

- [x] **Created Syslog Infrastructure Monitoring** dashboard
  - Comprehensive syslog server monitoring with 11 panels
  - Message rate tracking and processing latency
  - Severity and facility-based log filtering
  - Critical and error log highlighting
  - Recent events live tail
  - Documentation: `docs/GRAFANA_DASHBOARD_USAGE_GUIDE.md`

- [x] **Created CoreDNS Performance & Health** dashboard
  - 14 comprehensive monitoring panels
  - Query rate by DNS record type
  - Response time percentiles (P50, P95, P99)
  - Cache statistics and hit rate monitoring
  - Forward request tracking
  - Top queried domains table
  - Resource usage (CPU/Memory)
  - Plugin status monitoring
  - Documentation: `docs/GRAFANA_DASHBOARD_USAGE_GUIDE.md`

**REMAINING ACTIONS:**

- [ ] **Deploy and Configure IPMI Exporter on Homelab Node**
  - Follow guide: `docs/RHEL10_HOMELAB_METRICS_SETUP.md`
  - Install IPMI exporter on 192.168.4.62
  - Configure IPMI credentials
  - Verify IPMI Hardware Monitoring dashboard shows data

- [ ] **Fix Prometheus Pod Status (1/2 Ready)**
  - Run diagnostics: `./scripts/diagnose-monitoring-stack.sh`
  - Check if fix from AI_AGENT_IMPLEMENTATION_REPORT.md was applied
  - Verify runAsGroup: 65534 in prometheus.yaml securityContext
  - Check Loki frontend_worker is disabled
  - Run remediation if needed: `./scripts/remediate-monitoring-stack.sh`

- [ ] **Verify Grafana Datasource Connectivity**
  - Access Grafana: http://192.168.4.63:30300
  - Navigate to Configuration → Data Sources
  - Test Prometheus datasource connection
  - Test Loki datasource connection
  - Review endpoints: `kubectl get endpoints -n monitoring prometheus loki`

#### Prometheus Targets Down

**IMPORTANT:** Before troubleshooting, deploy monitoring stack with new dashboards:
```bash
cd /srv/monitoring_data/VMStation
git pull
./deploy.sh monitoring
```

Current down targets from problem statement require investigation:

- [ ] `192.168.4.62:9290` - **ipmi-exporter on homelab**
  - **Status:** Not yet deployed
  - **Action:** Follow setup guide: `docs/RHEL10_HOMELAB_METRICS_SETUP.md` section 3
  - **Steps:**
    1. SSH to homelab: `ssh root@192.168.4.62`
    2. Install IPMI tools: `dnf install -y ipmitool freeipmi`
    3. Download and install ipmi_exporter
    4. Create systemd service with CAP_SYS_RAWIO capability
    5. Configure firewall: `firewall-cmd --add-port=9290/tcp --permanent`
    6. Verify in Prometheus targets after restart
  
- [ ] `192.168.4.62:9100` - **node-exporter on homelab**
  - **Status:** Likely not installed
  - **Action:** Follow setup guide: `docs/RHEL10_HOMELAB_METRICS_SETUP.md` section 1
  - **Steps:**
    1. SSH to homelab: `ssh root@192.168.4.62`
    2. Download and install node_exporter
    3. Create systemd service
    4. Configure firewall: `firewall-cmd --add-port=9100/tcp --permanent`
    5. Test from masternode: `curl http://192.168.4.62:9100/metrics`
    6. Verify in Prometheus targets
  
- [ ] `192.168.4.61:9100` - **node-exporter on storagenodet3500**
  - **Status:** Should be deployed by Ansible already
  - **Action:** Verify deployment and connectivity
  - **Steps:**
    1. SSH to storagenodet3500: `ssh root@192.168.4.61`
    2. Check service: `systemctl status node_exporter`
    3. Test locally: `curl http://localhost:9100/metrics`
    4. Check firewall on Debian: `ufw status` or `iptables -L`
    5. Test from masternode: `curl http://192.168.4.61:9100/metrics`
    6. Review Ansible logs for deployment errors
  
- [ ] `192.168.4.63:9100` - **node-exporter on masternode**
  - **Status:** Should be deployed by Ansible already
  - **Action:** Verify deployment and connectivity
  - **Steps:**
    1. Check service: `systemctl status node_exporter`
    2. Test locally: `curl http://localhost:9100/metrics`
    3. Verify in Prometheus targets at http://192.168.4.63:30090
    4. Review pod logs if using DaemonSet: `kubectl logs -n monitoring -l app=node-exporter`

**Diagnostic Commands:**
```bash
# Check all Prometheus targets status
curl http://192.168.4.63:30090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

# Verify Prometheus scrape config
kubectl get configmap prometheus-config -n monitoring -o yaml

# Check which targets are currently configured
grep -A 5 "job_name.*node-exporter\|job_name.*ipmi" manifests/monitoring/prometheus.yaml
```

### 🧪 Testing & Validation

#### Wake-on-LAN Testing
- [ ] Add WoL testing to ansible playbook execution
  - Sleep storagenodet3500 and homelab nodes
  - Send WoL magic packet to wake nodes
  - Measure wake time and log any errors
  - Document expected wake times for each node
  - **Implementation:** Create `ansible/playbooks/test-wol.yaml`
  
#### Curl Output Reduction
- [ ] Reduce curl request output verbosity in scripts/logs
  - Current issue: "egregious size/length in terminal"
  - Solution: Use `curl -s` with custom output formatting
  - Format: "curl ip:port ok" or "curl ip:port ERROR: <reason>"
  - **Files to update:** Any scripts executing curl with verbose output

## SSO / Kerberos (FreeIPA) Deployment — provide network SSO for home

Goal: run a Kerberos/FreeIPA identity service on the control-plane (masternode) to enable SSO for Samba shares and Wi‑Fi (via RADIUS) for the home network. Intended for homelab/POC use — follow hardening checklist before trusting in production.

Checklist:
- [ ] Decide deployment target: Kubernetes pod on masternode (hostNetwork) or dedicated VM on `homelab` (recommended for production)
- [ ] Create manifest: `manifests/idm/freeipa-statefulset.yaml` (StatefulSet, hostNetwork: true, nodeSelector -> control-plane, persistent storage)
- [ ] Provision storage on masternode: PV or hostPath (example: `/var/lib/freeipa`) with proper ownership and backups
- [ ] Ensure time sync: install/configure `chrony` or `ntpd` on masternode and all clients (Kerberos sensitive to clock drift)
- [ ] Network hardening: NetworkPolicy + host firewall to restrict access to ports 88/464/749/389/636 and only allow trusted subnets (e.g., 192.168.4.0/24)
- [ ] Deploy FreeRADIUS (or integrate RADIUS with FreeIPA) for 802.1X Wi‑Fi authentication
- [ ] Create service principal(s) and keytabs for servers (Samba) and distribute securely to `storagenodet3500`
- [ ] Configure Samba/SSSD on `storagenodet3500` to use Kerberos/LDAP for auth and join the realm
- [ ] Backup & DR: schedule automated KDC DB + keytab backups to external storage
- [ ] Monitoring & alerts: add lightweight KDC health checks to Prometheus (scrape node exporter + process checks)
- [ ] Document exact commands and manifests in `docs/IDM_DEPLOYMENT.md`

Quick commands / verification (examples):
```bash
# apply manifest (after editing)
kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f manifests/idm/freeipa-statefulset.yaml

# watch startup logs
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n idm get pods -w
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n idm logs -l app=freeipa --tail=200

# inside pod: create service principal & keytab for Samba (example)
# kubectl exec -n idm -it freeipa-0 -- ipa service-add host/storagenodet3500.example.internal
# kubectl exec -n idm -it freeipa-0 -- ipa-getkeytab -s freeipa.example.internal -p host/storagenodet3500.example.internal -k /tmp/samba.keytab

# on storagenodet3500: test kerberos and samba
# kinit admin@EXAMPLE.INTERNAL
# smbclient //storagenodet3500/share -k -U user@EXAMPLE.INTERNAL
```

Security notes:
- Running a KDC inside Kubernetes is acceptable for a lab/PoC but treat the KDC as a high-value asset: isolate it, lock network access, use strong secrets, and back up frequently.
- Prefer a dedicated VM for production identity services. If using Kubernetes: use hostNetwork, persistent PV, strict NetworkPolicy, and RBAC-limited Secrets.

Docs / follow-ups:
- Add `manifests/idm/freeipa-statefulset.yaml` (template) and `docs/IDM_DEPLOYMENT.md` with step-by-step commands, keytab procedures, and backup instructions.


 
---

### 🚀 New Infrastructure - Scaffolding Required

#### CCNA Practice Lab Deployment ✅ COMPLETE
**Status:** Ready for deployment  
**Location:** `terraform/ccna-lab/`  
**Documentation:** `terraform/ccna-lab/README.md`

Create Terraform infrastructure for CCNA practice environment with Cisco routers, network visualization, and complete isolation from production.

**Deployment Workflow:**

```bash
# 1. Prepare homelab node (run on homelab: 192.168.4.62)
ssh root@192.168.4.62
cd /tmp
# Download and run setup script from your workstation
./terraform/ccna-lab/scripts/setup-homelab.sh

# 2. Copy Cisco IOS images to homelab
scp c7200-advipservicesk9-mz.152-4.S5.bin root@192.168.4.62:/var/lib/libvirt/images/cisco/
scp c7200p-advipsericesk9-mz.152-4.M.bin root@192.168.4.62:/var/lib/libvirt/images/cisco/

# 3. Deploy from workstation
cd f:\VMStation\terraform\ccna-lab
terraform init
terraform plan
terraform apply

# 4. Access GNS3 Web UI via SSH tunnel
ssh -L 3080:10.100.0.10:3080 root@192.168.4.62
# Open browser: http://localhost:3080

# 5. Create routers in GNS3 Web UI
# - Add Dynamips routers with your IOS images
# - Configure network topology
# - Connect routers and VMs
# - Start devices and practice CCNA scenarios

# 6. Monitor topology (optional)
python3 scripts/generate-topology.py
python3 scripts/monitor-links.py

# 7. Test network isolation
./scripts/test-isolation.sh

# 8. Destroy lab when done
./scripts/destroy-lab.sh
```

**Components Deployed:**
- [x] GNS3 server with Dynamips (Cisco router emulation)
- [x] 3 Cisco routers (configurable via GNS3 Web UI)
- [x] Ubuntu server VMs (default: 2, configurable)
- [x] Isolated networks (10.100.0.0/16)
- [x] Network visualization via GNS3 Web UI
- [x] REST API for automation
- [x] Complete isolation from production (192.168.4.0/24)

**Network Topology:**
```
Management: 10.100.0.0/24   (GNS3 server)
Routers:    10.100.1.0/24   (Cisco router interconnects)
Clients:    10.100.2.0/24   (Ubuntu/Windows VMs)
Practice:   10.100.10-30.0/24 (CCNA lab exercises)
```

**Access Methods:**
- GNS3 Web UI: http://localhost:3080 (via SSH tunnel)
- REST API: http://10.100.0.10:3080/v3
- Router consoles: Via GNS3 Web UI or telnet
- Ubuntu VMs: SSH to IPs from client network
- Topology visualization: Python scripts in scripts/

**Security:**
- ✓ Complete network isolation (no route to 192.168.4.0/24)
- ✓ Firewall rules enforced on homelab host
- ✓ No internet access by default
- ✓ Management only via SSH

**Documentation:**
- Main README: `terraform/ccna-lab/README.md`
- Architecture diagrams included
- Step-by-step deployment guide
- Troubleshooting section
- CCNA practice scenarios

**Estimated Deployment Time:** 30-45 minutes (including image upload)

---

#### Malware Analysis Lab Deployment
Create Terraform infrastructure for isolated malware analysis environment:

* do not want to rely on internet downloads for large image pulls, I pre-downloaded some apps/system images that I want to store in a local repo that the machine can pull whenever necessary for a deployment. How do we set this up? Should it only be on the homelab node to create a seperate space for homelab only stuff and media serving stuff on the storagenodet3500? I have cisco switch OS images, splunk setup msi, the linux distro images, windows server 2019 images etc.

**Directory Structure:**
```
terraform/malware-lab/
├── README.md
├── main.tf
├── variables.tf
├── outputs.tf
├── modules/
│   ├── windows-server/
│   ├── linux-enterprise/
│   ├── cisco-switch/
│   ├── ids-ips/
│   ├── rke2-splunk/
│   └── security-services/
└── environments/
    ├── dev/
    └── prod/
```

**Components to Deploy:**
- [ ] **Windows Server VMs** - Mixed versions for malware testing
  - Windows Server 2019
  - Windows Server 2022
  - Isolated network segments
  
- [ ] **Enterprise Linux VMs** - Free enterprise-grade distributions
  - Rocky Linux 9
  - AlmaLinux 9
  - Oracle Linux 9
  - Isolated network segments
  
- [ ] **Network Infrastructure**
  - Cisco switch simulation (GNS3/EVE-NG integration)
  - VLAN segmentation for isolation
  - Traffic mirroring for analysis
  
- [ ] **Security Solutions**
  - IDS/IPS deployment (Suricata or Snort)
  - Network tap/span configuration
  - SSL/TLS inspection capabilities
  
- [ ] **RKE2 + Splunk Enterprise**
  - RKE2 container for Splunk deployment
  - Splunk Enterprise (free tier)
  - Log forwarding from all lab VMs
  - SIEM dashboard templates
  
- [ ] **Enterprise Security Services**
  - CoreDNS server for lab DNS
  - DHCP server (dnsmasq or ISC DHCP)
  - Kerberos KDC for authentication testing
  - Active Directory Domain Controller (Windows)
  - Certificate Authority (PKI infrastructure)
  - LDAP/AD integration testing

**Deployment Target:**
- Primary: homelab node (192.168.4.62) - RHEL10
- Alternative: Separate VM host if homelab lacks resources
- Network: Isolated from production VMStation cluster
- Storage: Separate dataset/volume for lab VMs

**Next Steps:**
1. [ ] Create initial Terraform scaffold in `terraform/malware-lab/README.md`
2. [ ] Document resource requirements (CPU, RAM, Storage)
3. [ ] Create network isolation design document
4. [ ] Build TODO checklist for incremental deployment
5. [ ] Test basic Terraform deployment on homelab node

**Security Considerations:**
- Complete network isolation from production
- No internet access from malware VMs by default
- Snapshot-based rollback for infected systems
- Automated cleanup after analysis sessions
- Encrypted storage for malware samples

---

## Learning Resources

- Free Splunk Enterprise local instance
- Hallie Shaw's Splunk Power User course on Udemy
- https://app.letsdefend.io/path/soc-analyst-learning-path

---

## Notes

- CNI plugin fix ensures all worker nodes have required network plugins
- IPMI monitoring requires credentials - currently optional
- Monitoring dashboards need data sources verified and configured
- WoL testing will validate power management automation
- Malware lab should remain completely isolated from production cluster