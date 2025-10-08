# VMStation TODO List

## Immediate Issues - January 2025

### ✅ Fixed Issues
- [x] **CNI Plugin Installation** - Fixed loopback plugin missing on worker nodes (storagenodet3500)
  - Root cause: CNI plugins only installed on masternode
  - Solution: Moved installation to Phase 0 on all Debian nodes
  - Documentation: `docs/CNI_PLUGIN_FIX_JAN2025.md`

### 🔧 Monitoring & Observability

#### IPMI Hardware Monitoring
- [ ] Install IPMI exporter or IDrac exporter for hardware monitoring
  - Requires IPMI credentials for remote access
  - Target: homelab (RHEL10) node at 192.168.4.62
  - Expected metric endpoint: `http://192.168.4.62:9290`
  - Current status: Down (no credentials configured)
  - **Action:** Document IPMI credential requirements in manifests/monitoring/ipmi-exporter

#### Dashboard Issues (0 Entries)
- [ ] Fix **IPMI Hardware Monitoring - RHEL 10 Enterprise Server** dashboard
  - Depends on IPMI exporter deployment above
  
- [ ] Fix **vmstation** dashboard
  - Investigate missing data source or query issues
  
- [ ] Fix **Loki Logs & Aggregation** dashboard
  - Error: `dial tcp: lookup loki on 10.96.0.10:53: no such host`
  - Root cause: Loki service not deployed or DNS resolution failing
  - **Action:** Deploy Loki log aggregation stack or remove dashboard
  
- [ ] Fix **Node Metrics - Detailed System Monitoring** dashboard
  - Verify node-exporter pods are running on all nodes
  - Check Prometheus scrape configs include all nodes
  
- [ ] Fix **VMStation Kubernetes Cluster Overview** dashboard
  - Verify all data sources are configured correctly

#### Prometheus Targets Down
Current down targets from problem statement:
- [ ] `192.168.4.62:9290` - ipmi-exporter on homelab (needs credentials)
- [ ] `192.168.4.61:9100` - node-exporter on storagenodet3500 (needs investigation)
- [ ] `192.168.4.62:9100` - node-exporter on homelab (needs investigation)  
- [ ] `192.168.4.63:9100` - node-exporter on masternode (needs investigation)

**Actions:**
1. SSH to each node and verify node-exporter is running: `systemctl status node_exporter`
2. Check firewall rules allow port 9100 access
3. Verify Prometheus scrape configs in `manifests/monitoring/prometheus.yaml`
4. Check node-exporter deployment manifest for correct node selectors

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

### 🚀 New Infrastructure - Scaffolding Required

#### Malware Analysis Lab Deployment
Create Terraform infrastructure for isolated malware analysis environment:

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
