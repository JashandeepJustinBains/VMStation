# Kubespray Automation Workflow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     GitHub Actions Trigger                       │
│              (Manual: workflow_dispatch)                         │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Runner Setup & Dependencies                     │
│  • Install Ansible, wakeonlan, jq, curl, git                   │
│  • Setup SSH configuration & known_hosts                        │
│  • Configure Git (user.name, user.email)                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              Execute: ops-kubespray-automation.sh                │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
    ┌────────────────────────────────────────────────────────┐
    │  STEP 1: Prepare Runtime Environment                   │
    │  • Create directories (artifacts, logs, backups)       │
    │  • Write SSH key from secret (mode 0600)               │
    │  • Setup git config if needed                          │
    │  • Add hosts to known_hosts                            │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────────────────────┐
    │  STEP 2: Backup Important Files                        │
    │  • Backup inventory files                              │
    │  • Backup deploy.sh, playbooks                         │
    │  • Store in .git/ops-backups/<timestamp>/              │
    │  • Commit backup to git                                │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────────────────────┐
    │  STEP 3: Normalize Inventory                           │
    │  • Check Kubespray inventory exists                    │
    │  • Copy/normalize from main inventory if needed        │
    │  • Ensure consistent group names                       │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────────────────────┐
    │  STEP 3.5: Validate Inventory                          │
    │  • ansible all -m ping                                 │
    │  • Test connectivity to all nodes                      │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ├─── FAIL ───┐
                         │             │
                         │             ▼
                         │    ┌────────────────────────────┐
                         │    │  Wake-on-LAN Remediation   │
                         │    │  • Send WoL to all nodes   │
                         │    │  • Wait 90 seconds         │
                         │    │  • Retry ping              │
                         │    └────────────┬───────────────┘
                         │                 │
                         │                 ├─── FAIL ───┐
                         │                 │             │
                         │                 │             ▼
                         │                 │    ┌────────────────────┐
                         │                 │    │  Create Diagnostic │
                         │                 │    │  Bundle & EXIT     │
                         │                 │    └────────────────────┘
                         │                 │
                         ▼─────────────────┘
    ┌────────────────────────────────────────────────────────┐
    │  STEP 4: Preflight Checks (RHEL10)                     │
    │  • Run run-preflight-rhel10.yml                        │
    │  • Validate Python, swap, firewall, SELinux            │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ├─── FAIL ───┐
                         │             │
                         │             ▼
                         │    ┌────────────────────────────┐
                         │    │  Preflight Remediation     │
                         │    │  • Install Python          │
                         │    │  • Disable swap            │
                         │    │  • Load kernel modules     │
                         │    │  • Retry preflight         │
                         │    └────────────┬───────────────┘
                         │                 │
                         ▼─────────────────┘
    ┌────────────────────────────────────────────────────────┐
    │  STEP 4.5: Create Idempotent Fix Playbooks             │
    │  • disable-swap.yml                                    │
    │  • load-kernel-modules.yml                             │
    │  • restart-container-runtime.yml                       │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────────────────────┐
    │  STEP 5: Setup Kubespray                               │
    │  • Run scripts/run-kubespray.sh                        │
    │  • Clone/update Kubespray repo                         │
    │  • Create Python venv                                  │
    │  • Install Ansible dependencies                        │
    │  • Copy inventory to Kubespray                         │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────────────────────┐
    │  STEP 6: Deploy Kubernetes Cluster                     │
    │  • cd to Kubespray dir                                 │
    │  • Activate venv                                       │
    │  • ansible-playbook cluster.yml (retry up to 3x)      │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ├─── FAIL ───┐
                         │             │
                         │             ▼
                         │    ┌────────────────────────────┐
                         │    │  Cluster Remediation       │
                         │    │  • Restart kubelet         │
                         │    │  • Restart containerd      │
                         │    │  • Retry deployment        │
                         │    └────────────┬───────────────┘
                         │                 │
                         ▼─────────────────┘
    ┌────────────────────────────────────────────────────────┐
    │  STEP 7: Setup Kubeconfig                              │
    │  • Copy admin.conf to /tmp/admin.conf                  │
    │  • Set permissions (mode 0600)                         │
    │  • Distribute to control-plane nodes                   │
    │  • Export KUBECONFIG=/tmp/admin.conf                   │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────────────────────┐
    │  STEP 8: Verify Cluster Health                         │
    │  • kubectl wait --for=condition=Ready nodes --all      │
    │  • Check kube-system pods                              │
    │  • Verify CNI pods are Running                         │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ├─── FAIL ───┐
                         │             │
                         │             ▼
                         │    ┌────────────────────────────┐
                         │    │  CNI Remediation           │
                         │    │  • Load kernel modules     │
                         │    │  • Restart CNI pods        │
                         │    │  • Verify again            │
                         │    └────────────┬───────────────┘
                         │                 │
                         ▼─────────────────┘
    ┌────────────────────────────────────────────────────────┐
    │  STEP 9: Deploy Monitoring Stack                       │
    │  • ./deploy.sh monitoring                              │
    │  • Deploy Prometheus, Grafana, Loki                    │
    │  • Deploy Node Exporter, Kube State Metrics            │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────────────────────┐
    │  STEP 10: Deploy Infrastructure Services               │
    │  • ./deploy.sh infrastructure                          │
    │  • Deploy NTP/Chrony, Syslog, Kerberos                 │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────────────────────┐
    │  STEP 11: Create and Run Smoke Tests                   │
    │  • Generate tests/kubespray-smoke.sh                   │
    │  • Create test namespace                               │
    │  • Deploy test pod and service                         │
    │  • Validate basic functionality                        │
    │  • Cleanup test resources                              │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────────────────────┐
    │  STEP 12: Generate Report                              │
    │  • Collect node information                            │
    │  • Check preflight status                              │
    │  • Check cluster deployment status                     │
    │  • Create ops-report-<timestamp>.json                  │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────────────────────┐
    │  STEP 13: Security Cleanup                             │
    │  • Log cleanup reminder                                │
    │  • Document key rotation procedure                     │
    └────────────────────┬───────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              Collect Artifacts (GitHub Actions)                  │
│  • Logs: ansible/artifacts/run-*/ansible-run-logs/             │
│  • Reports: ops-report-*.json                                   │
│  • Kubeconfig: /tmp/admin.conf (7-day retention)               │
│  • Diagnostic Bundle (if failures)                             │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Display Summary & Status                      │
│  • Show deployment results                                      │
│  • Link to artifacts                                            │
│  • Success/Warning/Error status                                │
└─────────────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════

KEY FEATURES:

🔄 Retry Logic:
   - Inventory validation: 2 attempts (with WoL)
   - Preflight checks: 2 attempts (with remediation)
   - Cluster deployment: 3 attempts (with remediation)

🛡️ Error Handling:
   - Network isolation → Diagnostic bundle + Exit
   - Preflight failures → Auto remediation + Retry
   - Cluster failures → Restart services + Retry
   - CNI issues → Load modules + Restart pods

📊 Artifact Collection:
   - 10+ detailed log files
   - JSON status reports
   - Diagnostic bundles on failure
   - Kubeconfig for cluster access
   - Timestamped backups

🔐 Security:
   - SSH keys from GitHub Secrets (mode 0600)
   - Kubeconfig protected (mode 0600, .gitignore)
   - No secrets in logs or git
   - Automatic backups to git history

═══════════════════════════════════════════════════════════════════
```

## Error Handling Flow

```
┌────────────────┐
│  Any Step Fails│
└───────┬────────┘
        │
        ▼
   ┌─────────────────────┐
   │ Log Error & Details │
   └─────────┬───────────┘
             │
             ▼
   ┌──────────────────────────┐
   │ Attempt Auto-Remediation │
   │ (if applicable)          │
   └─────────┬────────────────┘
             │
      ┌──────┴──────┐
      │             │
      ▼             ▼
   SUCCESS       FAILURE
      │             │
      │             ▼
      │      ┌──────────────┐
      │      │ Retry Logic? │
      │      └──────┬───────┘
      │             │
      │      ┌──────┴──────┐
      │      │             │
      │      ▼             ▼
      │    RETRY      NO RETRIES
      │      │             │
      │      └──────┬──────┘
      │             │
      │             ▼
      │      ┌──────────────────┐
      │      │ Create Diagnostic│
      │      │ Bundle           │
      │      └──────┬───────────┘
      │             │
      │             ▼
      │      ┌──────────────────┐
      │      │ Generate Report  │
      │      └──────┬───────────┘
      │             │
      │             ▼
      │      ┌──────────────────┐
      │      │ Exit with Error  │
      │      └──────────────────┘
      │
      ▼
┌──────────────┐
│ Continue to  │
│ Next Step    │
└──────────────┘
```

## Parallel Operations

```
After Cluster Deployment:
┌─────────────────────────────────────┐
│     Setup Kubeconfig (Step 7)       │
└───────────────┬─────────────────────┘
                │
                ▼
┌───────────────────────────────────────────┐
│      Verify Cluster (Step 8)              │
│      (Nodes Ready, CNI Healthy)           │
└───────────────┬───────────────────────────┘
                │
                ▼
        ┌───────┴────────┐
        │                │
        ▼                ▼
┌───────────────┐  ┌─────────────────┐
│   Monitoring  │  │ Infrastructure  │
│  Deployment   │  │   Deployment    │
│   (Step 9)    │  │    (Step 10)    │
└───────┬───────┘  └────────┬────────┘
        │                   │
        └───────┬───────────┘
                │
                ▼
        ┌───────────────┐
        │  Smoke Tests  │
        │   (Step 11)   │
        └───────────────┘
```
