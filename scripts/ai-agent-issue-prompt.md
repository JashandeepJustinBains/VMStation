AI Agent Task: Diagnose and remediate monitoring stack failures (use `Output_for_Copilot.txt` for context)

Context (from `Output_for_Copilot.txt`):
- Cluster type: kubeadm on Debian Bookworm control-plane + workers; RHEL10 homelab nodes mentioned (not primary here).
- Monitoring stack deployed by Ansible: Prometheus (StatefulSet), Loki (StatefulSet), Grafana (Deployment), Promtail (DaemonSet), node-exporter (DaemonSet), syslog-ng, blackbox-exporter.
- Storage: PVs created for prometheus, loki, grafana, promtail; PVCs are Bound (storage binding succeeded).

Observed runtime failures (as logged):
1) Prometheus pod `prometheus-0` is looping (CrashLoopBackOff / Error). Prometheus is not Ready and restarts repeatedly.
   - Symptom: CrashLoopBackOff; readiness/unreadiness events present; prometheus headless service shows no endpoints.
2) Loki pod `loki-0` is Running but not Ready. It shows restarts and does not become Ready.
   - Symptom: readiness probe failing or startup error; loki headless service has no endpoints.
3) Headless services for Prometheus and Loki exist (ClusterIP: None) but have empty endpoints lists; Grafana queries to `prometheus.monitoring.svc.cluster.local` and `loki.monitoring.svc.cluster.local` return "no such host" or empty results.
   - Symptom: Services exist but endpoints are empty because pods are not Ready.
4) Grafana pod is Running and reports 'OK', but cannot reach Prometheus/Loki due to the empty endpoints.
5) PVCs are Bound — PV provisioning is not the immediate failure point, but permission/ownership on hostPath mounts or incorrect volume mounts could cause the pod startup failures.
6) syslog-ng shows warnings about deprecated config format and capability errors (not blocking monitoring but flagged in logs).

Likely root causes to investigate (hypothesis list):
- Permission/ownership issues on hostPath directories used by Prometheus/Loki PVs (e.g., wrong uid/gid preventing the container process from writing). Check host directory ownership under `/srv/monitoring_data/*` on the masternode.
- ConfigMap or startup configuration errors for Prometheus or Loki (invalid YAML, missing required fields, or index/WAL corruption causing restarts).
- Readiness or liveness probe misconfiguration causing pods to be marked Unready unnecessarily.
- VolumeMount path mismatches inside containers (paths expected by app not matching mounted paths from PVs/PVCs).
- Image/compatibility issues (e.g., process user in container expects specific privileges; syslog-ng capability issues hint at capability drops).

Task for the AI agent (step-by-step):
1) Read `Output_for_Copilot.txt` to extract exact pod event messages and timestamps for Prometheus and Loki; include the last N lines (configurable, default 500) of their logs.
2) Run the following kubectl commands (dry-run where applicable) and capture their outputs for diagnosis:
   - kubectl -n monitoring describe pod prometheus-0
   - kubectl -n monitoring logs prometheus-0 --previous || kubectl -n monitoring logs prometheus-0
   - kubectl -n monitoring describe pod loki-0
   - kubectl -n monitoring logs loki-0
   - kubectl -n monitoring get endpoints prometheus -o yaml
   - kubectl -n monitoring get endpoints loki -o yaml
   - kubectl -n monitoring get pvc,pv -o wide
   - kubectl -n monitoring get pods -o wide
3) If logs show permission or file ownership errors (e.g., EACCES, permission denied), then:
   - SSH to the masternode and check the hostPath directories (e.g., `/srv/monitoring_data/prometheus`, `/srv/monitoring_data/loki`) and their ownership. Commands (example):
     - ls -la /srv/monitoring_data
     - stat /srv/monitoring_data/prometheus
   - If ownership mismatches are present, chown the directory to the expected UID/GID used by the container (or update the StatefulSet to run as the expected user).
   - Recreate pods where necessary: kubectl -n monitoring delete pod prometheus-0 --wait
4) If logs show config parsing errors, output the offending ConfigMap and propose a corrected patch. Use `kubectl -n monitoring get configmap -o yaml` to retrieve.
5) If readiness probe failures are the cause, analyze probe config in StatefulSet and propose relaxing probe (increase initialDelaySeconds or failureThreshold) as a temporary fix while root-cause is addressed.
6) If WAL/index corruption is suspected for Prometheus, propose creating a backup of the problematic data directory and starting Prometheus with an option to recover or reinitialize (document data-loss impact). Prefer backup before destructive steps.
7) After applying fixes, validate endpoints are populated and Grafana can query Prometheus/Loki.

Constraints and safety:
- Do not delete PVCs or PVs unless explicitly asked — prefer non-destructive fixes first.
- Always take backups of hostPath directories before destructive operations.
- When patching ConfigMaps or StatefulSets, produce small patches and present them for human review before applying.

Outputs expected from the agent:
- A structured diagnostic report containing the exact `kubectl describe` and `kubectl logs` outputs for prometheus-0 and loki-0, and the endpoints and PVC/PV statuses.
- A prioritized remediation plan with specific commands/patches (kubectl patch or kubectl apply snippets) to fix the immediate causes.
- A safety checklist for any host-level changes (chown/chmod) including commands and the expected effects.
- If a change is applied, an automated validation sequence that checks endpoints and Grafana connectivity.

If you want me to run these kubectl commands here and produce the report automatically, confirm and provide kubeconfig or allow me to run the commands in your environment; otherwise, paste the `kubectl describe` and `kubectl logs` outputs here and I will analyze them and produce the remediation patches.
