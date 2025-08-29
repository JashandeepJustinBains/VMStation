# Premium GitHub Copilot Agent Complete Prompt with Embedded Diagnostics

## Overview

This document contains a complete, ready-to-paste prompt for the premium GitHub Copilot agent that includes actual diagnostic output from a VMStation cluster with monitoring stack issues. This prompt embeds the gathered diagnostics and follows all safety constraints.

## Usage

Copy the entire prompt below and paste it directly to the premium GitHub Copilot agent. No additional diagnostic gathering is needed as the cluster snapshot is already embedded.

---

## The Complete Prompt

You are an expert Kubernetes troubleshooting assistant. I will provide current diagnostics from my cluster; use them exactly when referencing node names/IPs and failing pods. Produce a safe, repeatable triage and remediation plan an operator will run manually.

### Cluster and constraints (use these hostnames exactly)
- masternode — 192.168.4.63
- storagenodet3500 — 192.168.4.61
- localhost.localdomain — 192.168.4.62

### Hard constraints (MUST follow)
- Do NOT modify file permissions, create directories, or apply changes automatically.
- Provide exact shell/kubectl/ansible commands for the operator to run manually; prefix each command with a short purpose and expected safe outcome.
- Mark any command that would change node filesystem state with "operator-only: modifies node filesystem" and require explicit operator confirmation.
- Prefer minimally invasive, idempotent checks first. When multiple fixes exist, show the least invasive first.
- Use the hostnames above whenever a node is referenced.

### Cluster snapshot (use this output as the authoritative cluster state)
--- begin snapshot ---
=== Gathering Basic K8s Monitoring Diagnostics ===

# Cluster and node information
kubectl get nodes -o wide
NAME                    STATUS   ROLES           AGE     VERSION    INTERNAL-IP    EXTERNAL-IP   OS-IMAGE                                   KERNEL-VERSION                CONTAINER-RUNTIME
localhost.localdomain   Ready    <none>          2d18h   v1.29.15   192.168.4.62   <none>        Red Hat Enterprise Linux 10.0 (Coughlan)   6.12.0-55.9.1.el10_0.x86_64   containerd://1.7.27
masternode              Ready    control-plane   3d18h   v1.29.15   192.168.4.63   <none>        Debian GNU/Linux 12 (bookworm)             6.1.0-32-amd64                containerd://1.6.20
storagenodet3500        Ready    <none>          3d18h   v1.29.15   192.168.4.61   <none>        Debian GNU/Linux 12 (bookworm)             6.1.0-34-amd64                containerd://1.6.20

# Monitoring namespace pods
kubectl -n monitoring get pods -o wide
NAME                                                        READY   STATUS                  RESTARTS         AGE     IP             NODE                    NOMINATED NODE   READINESS GATES
alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running                 0                3h31m   10.244.0.14    masternode              <none>           <none>
debug-chown                                                 0/1     Completed               0                120m    <none>         masternode              <none>           <none>
kube-prometheus-stack-grafana-878594f88-cdbzt               0/3     Init:CrashLoopBackOff   53 (66s ago)     117m    10.244.0.23    masternode              <none>           <none>
kube-prometheus-stack-grafana-8c4bb9b97-7prbs               0/3     Init:CrashLoopBackOff   53 (56s ago)     117m    10.244.0.24    masternode              <none>           <none>
kube-prometheus-stack-kube-state-metrics-746bfb7fd8-7gkbv   1/1     Running                 74 (3h33m ago)   3d1h    10.244.1.13    storagenodet3500        <none>           <none>
kube-prometheus-stack-operator-68d8df4c4b-brlbw             1/1     Running                 0                138m    10.244.2.13    localhost.localdomain   <none>           <none>
kube-prometheus-stack-prometheus-node-exporter-78v74        1/1     Running                 0                2d18h   192.168.4.62   localhost.localdomain   <none>           <none>
kube-prometheus-stack-prometheus-node-exporter-92cm5        1/1     Running                 1 (3d5h ago)     3d6h    192.168.4.61   storagenodet3500        <none>           <none>
kube-prometheus-stack-prometheus-node-exporter-gfxrg        1/1     Running                 1 (2d6h ago)     3d6h    192.168.4.63   masternode              <none>           <none>
loki-stack-0                                                0/1     CrashLoopBackOff        54 (56s ago)     123m    10.244.0.20    masternode              <none>           <none>
loki-stack-promtail-k8cds                                   1/1     Running                 0                3h29m   10.244.1.29    storagenodet3500        <none>           <none>
loki-stack-promtail-nlt5f                                   0/1     Running                 0                3h28m   10.244.0.13    masternode              <none>           <none>
loki-stack-promtail-s99hk                                   1/1     Running                 0                3h28m   10.244.2.12    localhost.localdomain   <none>           <none>
prometheus-kube-prometheus-stack-prometheus-0               2/2     Running                 0                3h31m   10.244.0.17    masternode              <none>           <none>

# Recent events in monitoring namespace
kubectl -n monitoring get events --sort-by='.lastTimestamp' | tail -20
24m         Normal    Started                pod/loki-stack-0                                                Started container loki
24m         Normal    Created                pod/loki-stack-0                                                Created container: loki
22m         Warning   Unhealthy              pod/loki-stack-promtail-nlt5f                                   Readiness probe failed: Get "http://10.244.0.13:3101/ready": context deadline exceeded (Client.Timeout exceeded while awaiting headers)
6m24s       Warning   BackOff                pod/loki-stack-0                                                Back-off restarting failed container loki in pod loki-stack-0_monitoring(299e614d-fb74-4d6f-a058-f5fb02c3a111)
6m23s       Warning   BackOff                pod/kube-prometheus-stack-grafana-8c4bb9b97-7prbs               Back-off restarting failed container init-chown-data in pod kube-prometheus-stack-grafana-8c4bb9b97-7prbs_monitoring(b7d041e1-9fd2-4429-9d68-4786377d0a59)
6m16s       Warning   BackOff                pod/kube-prometheus-stack-grafana-878594f88-cdbzt               Back-off restarting failed container init-chown-data in pod kube-prometheus-stack-grafana-878594f88-cdbzt_monitoring(80ef4c52-41cc-4905-bf76-a0b0791c41ae)
3m50s       Normal    TaintManagerEviction   pod/kube-prometheus-stack-kube-state-metrics-746bfb7fd8-7gkbv   Cancelling deletion of Pod monitoring/kube-prometheus-stack-kube-state-metrics-746bfb7fd8-7gkbv
2m30s       Normal    Pulled                 pod/loki-stack-0                                                Container image "grafana/loki:2.9.2" already present on machine
2m30s       Normal    Started                pod/loki-stack-0                                                Started container loki
2m30s       Normal    Created                pod/loki-stack-0                                                Created container: loki
2m27s       Normal    Started                pod/kube-prometheus-stack-grafana-878594f88-cdbzt               Started container init-chown-data
2m27s       Normal    Created                pod/kube-prometheus-stack-grafana-8c4bb9b97-7prbs               Created container: init-chown-data
2m27s       Normal    Created                pod/kube-prometheus-stack-grafana-878594f88-cdbzt               Created container: init-chown-data
2m27s       Warning   BackOff                pod/loki-stack-0                                                Back-off restarting failed container loki in pod loki-stack-0_monitoring(299e614d-fb74-4d6f-a058-f5fb02c3a111)
2m27s       Normal    Pulled                 pod/kube-prometheus-stack-grafana-8c4bb9b97-7prbs               Container image "docker.io/library/busybox:1.31.1" already present on machine
2m27s       Normal    Pulled                 pod/kube-prometheus-stack-grafana-878594f88-cdbzt               Container image "docker.io/library/busybox:1.31.1" already present on machine
2m27s       Normal    Started                pod/kube-prometheus-stack-grafana-8c4bb9b97-7prbs               Started container init-chown-data
82s         Warning   BackOff                pod/kube-prometheus-stack-grafana-8c4bb9b97-7prbs               Back-off restarting failed container init-chown-data in pod kube-prometheus-stack-grafana-8c4bb9b97-7prbs_monitoring(b7d041e1-9fd2-4429-9d68-4786377d0a59)
81s         Warning   BackOff                pod/kube-prometheus-stack-grafana-878594f88-cdbzt               Back-off restarting failed container init-chown-data in pod kube-prometheus-stack-grafana-878594f88-cdbzt_monitoring(80ef4c52-41cc-4905-bf76-a0b0791c41ae)
7s          Warning   Unhealthy              pod/loki-stack-promtail-nlt5f                                   Readiness probe failed: Get "http://10.244.0.13:3101/ready": context deadline exceeded (Client.Timeout exceeded while awaiting headers)

# PVCs in monitoring namespace
kubectl -n monitoring get pvc
NAME                                                                                                   STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0   Bound    pvc-70be5a33-8fb8-40a1-b4fc-89c9bc0bec76   2Gi        RWO            local-path     <unset>                 3d6h
kube-prometheus-stack-grafana                                                                          Bound    pvc-480b2659-d6de-4256-941b-45c8c07559ce   5Gi        RWO            local-path     <unset>                 3d6h
prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0           Bound    pvc-9084244e-ecb1-4006-a4d4-bf0fbd35407a   10Gi       RWO            local-path     <unset>                 3d6h
storage-loki-stack-0                                                                                   Bound    pvc-e4ec3eb4-c0f0-42c5-ae37-e390c70b60f0   10Gi       RWO            local-path     <unset>                 3d6h
--- end snapshot ---

### What I want from you (deliverables)
1. Quick triage checklist — prioritized likely causes with exact detection commands and expected signs.
2. Per-failing-pod diagnostic recipe for:
   - kube-prometheus-stack-grafana-* (init-chown-data failures)
   - loki-stack-0 (CrashLoopBackOff)
   - loki-stack-promtail-nlt5f (readiness probe failures)
   For each: kubectl describe/logs/events commands, node-side inspection commands labeled "run on <hostname>", and operator-only suggested fixes (marked), each with verification commands.
3. RBAC & ServiceAccount checks with exact kubectl queries and minimal patch examples (do not apply).
4. Storage/PV/PVC checks and safe operator suggestions to rebind or recover PVCs (commands shown, not executed).
5. Manifest/config diff commands (live vs repo/helm values) and how to verify hostnames used in manifests are the three given hostnames.
6. Init-container specific commands to capture chown output and node stat/ls of mounted paths.
7. Node runtime log commands for both containerd and docker hosts.
8. 2–3 Ansible "check-only" tasks (YAML) that detect missing dirs/owners/SELinux contexts/unbound PVCs — in check_mode only.
9. Verification & smoke tests to confirm pods become Running/Ready.
10. A concise prioritized 3-step action plan with exact commands and verification after each step.

### Formatting rules for your response
- Use short numbered steps and one-liner commands; each command must be copy-paste ready for a Linux shell or kubectl context.
- When node shell commands are required, label them "run on <hostname>".
- For each diagnostic command include: purpose (1 short sentence), command, and 1–2 lines describing expected good vs bad output.
- Flag any filesystem-modifying command with "operator-only: modifies node filesystem" and require explicit operator confirmation.
- When suggesting manifest changes, show the minimal kubectl patch or helm values snippet and the verification command; do not apply them.

Priority: produce the diagnostic recipes and command sets first (1–7), then ansible check-only snippets (8), then verification scripts and the 3-step action plan (9–10). Keep answers concise and copy-paste ready.

---

## Instructions for Use

1. Copy the entire prompt above (from "You are an expert..." to "...copy-paste ready.")
2. Paste it directly to the premium GitHub Copilot agent
3. The agent will provide a comprehensive troubleshooting plan based on the embedded diagnostics
4. Follow the resulting action plan step-by-step

## Key Features

- ✅ Embedded diagnostic output from real cluster
- ✅ Enforces "no automatic filesystem changes" constraint
- ✅ Uses exact VMStation hostnames
- ✅ Prioritizes likely causes based on actual pod states
- ✅ Requests operator-safe commands with explanations
- ✅ Ready-to-paste format for immediate use

## Safety Guarantees

- No automatic execution of commands
- Clear marking of destructive operations  
- Step-by-step verification requirements
- Minimal, surgical fixes preferred
- Proper hostname usage enforced