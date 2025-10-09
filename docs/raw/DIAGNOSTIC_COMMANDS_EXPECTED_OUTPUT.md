# Diagnostic Commands & Expected Outputs - Post-Fix

This document provides the exact diagnostic commands requested in the problem statement and their expected outputs after applying the fixes.

## Required Diagnostic Steps (From Problem Statement)

### 1) Get pods and wide info

**Command:**
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pods -o wide
```

**Expected Output (After Fix):**
```
NAME                                  READY   STATUS    RESTARTS   AGE     IP           NODE               NOMINATED NODE   READINESS GATES
blackbox-exporter-xxxxxxxxx-xxxxx     1/1     Running   0          10m     10.244.0.x   masternode         <none>           <none>
grafana-xxxxxxxxx-xxxxx               1/1     Running   0          45m     10.244.0.x   masternode         <none>           <none>
kube-state-metrics-xxxxxxxxx-xxxxx    1/1     Running   0          45m     10.244.0.x   masternode         <none>           <none>
loki-xxxxxxxxx-xxxxx                  1/1     Running   0          10m     10.244.0.x   masternode         <none>           <none>
node-exporter-xxxxx                   1/1     Running   0          45m     192.168.4.63 masternode         <none>           <none>
node-exporter-xxxxx                   1/1     Running   0          45m     192.168.4.61 storagenodet3500   <none>           <none>
prometheus-xxxxxxxxx-xxxxx            1/1     Running   0          45m     10.244.0.x   masternode         <none>           <none>
promtail-xxxxx                        1/1     Running   0          45m     10.244.0.x   masternode         <none>           <none>
promtail-xxxxx                        1/1     Running   0          45m     10.244.1.x   storagenodet3500   <none>           <none>
```

**Key Changes from Error Output:**
- ✅ blackbox-exporter: `Running` (was `CrashLoopBackOff`)
- ✅ loki: `Running` (was `CrashLoopBackOff`)
- ✅ RESTARTS: `0` (was `11`)

---

### 2) Describe the deployment

**Command:**
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring describe deployment blackbox-exporter
```

**Expected Key Sections:**

```yaml
Name:                   blackbox-exporter
Namespace:              monitoring
...
Replicas:               1 desired | 1 updated | 1 total | 1 available | 0 unavailable
...
Pod Template:
  Labels:  app=blackbox-exporter
  Service Account:  blackbox-exporter
  Containers:
   blackbox-exporter:
    Image:        prom/blackbox-exporter:v0.25.0
    Port:         9115/TCP
    Host Port:    0/TCP
    Args:
      --config.file=/etc/blackbox/blackbox.yml
    ...
    Readiness:  http-get http://:http/metrics delay=5s timeout=1s period=10s #success=1 #failure=3
    Liveness:   http-get http://:http/metrics delay=10s timeout=1s period=20s #success=1 #failure=3
...
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Progressing    True    NewReplicaSetAvailable
  Available      True    MinimumReplicasAvailable
...
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  10m   deployment-controller  Scaled up replica set blackbox-exporter-xxxxxxxxx to 1
```

**Key Indicators:**
- ✅ Available: `1/1`
- ✅ Conditions: `Available: True`
- ✅ No error events

---

### 3) Describe the pod

**Command:**
```bash
POD=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pods -l app=blackbox-exporter -o name | head -n1)
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring describe $POD
```

**Expected Key Sections:**

```yaml
Name:             blackbox-exporter-xxxxxxxxx-xxxxx
Namespace:        monitoring
...
Status:           Running
IP:               10.244.0.x
...
Containers:
  blackbox-exporter:
    Container ID:  containerd://xxxxxx
    Image:         prom/blackbox-exporter:v0.25.0
    ...
    State:          Running
      Started:      <timestamp>
    Ready:          True
    Restart Count:  0
...
Conditions:
  Type              Status
  Initialized       True
  Ready             True
  ContainersReady   True
  PodScheduled      True
...
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  10m   default-scheduler  Successfully assigned monitoring/blackbox-exporter-xxx to masternode
  Normal  Pulled     10m   kubelet            Container image "prom/blackbox-exporter:v0.25.0" already present on machine
  Normal  Created    10m   kubelet            Created container blackbox-exporter
  Normal  Started    10m   kubelet            Started container blackbox-exporter
```

**Key Indicators:**
- ✅ Status: `Running`
- ✅ Ready: `True`
- ✅ Restart Count: `0`
- ✅ No error events

---

### 4) Pod logs

**Command:**
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring logs deployment/blackbox-exporter --tail=200
```

**Expected Output:**
```
level=info ts=2025-10-08T19:38:00.000Z caller=main.go:XXX msg="Starting blackbox_exporter" version=(version=0.25.0, branch=HEAD, revision=XXX)
level=info ts=2025-10-08T19:38:00.000Z caller=main.go:XXX msg="Build context" context="(go=go1.21.X, platform=linux/amd64, user=root@XXX, date=XXX)"
level=info ts=2025-10-08T19:38:00.000Z caller=main.go:XXX msg="Loaded config file" config=/etc/blackbox/blackbox.yml
level=info ts=2025-10-08T19:38:00.000Z caller=main.go:XXX msg="Listening on address" address=:9115
level=info ts=2025-10-08T19:38:00.000Z caller=tls_config.go:XXX msg="Listening on" address=[::]:9115
level=info ts=2025-10-08T19:38:00.000Z caller=tls_config.go:XXX msg="TLS is disabled." http2=false address=[::]:9115
```

**Key Indicators:**
- ✅ No config parsing errors
- ✅ "Loaded config file" message present
- ✅ "Listening on address" message present
- ❌ No "error parsing config file" or "field timeout not found" errors

**Loki Logs:**
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring logs deployment/loki --tail=200
```

**Expected Output:**
```
level=info ts=2025-10-08T19:38:00.000Z caller=main.go:XXX msg="Starting Loki" version=(version=2.9.2, branch=HEAD, revision=XXX)
level=info ts=2025-10-08T19:38:00.000Z caller=server.go:XXX msg="server listening on addresses" http=[::]:3100 grpc=[::]:9096
level=info ts=2025-10-08T19:38:00.000Z caller=module_service.go:XXX msg=initialising module=server
level=info ts=2025-10-08T19:38:00.000Z caller=module_service.go:XXX msg=initialising module=ingester
level=info ts=2025-10-08T19:38:00.000Z caller=loki.go:XXX msg="Loki started"
```

**Key Indicators:**
- ✅ No schema validation errors
- ✅ "Loki started" message present
- ❌ No "boltdb-shipper works best with 24h" error

---

### 5) Nodes, labels and taints

**Command:**
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes --show-labels
```

**Expected Output:**
```
NAME               STATUS   ROLES           AGE   VERSION    LABELS
masternode         Ready    control-plane   1h    v1.29.15   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=masternode,kubernetes.io/os=linux,node-role.kubernetes.io/control-plane=,node.kubernetes.io/exclude-from-external-load-balancers=
storagenodet3500   Ready    <none>          1h    v1.29.15   beta.kubernetes.io/arch=amd64,beta.kubernetes.io/os=linux,kubernetes.io/arch=amd64,kubernetes.io/hostname=storagenodet3500,kubernetes.io/os=linux
```

**Describe node taints:**
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf describe node masternode | sed -n '/Taints:/,/Unschedulable:/p'
```

**Expected Output:**
```
Taints:             node-role.kubernetes.io/control-plane:NoSchedule
Unschedulable:      false
```

```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf describe node storagenodet3500 | sed -n '/Taints:/,/Unschedulable:/p'
```

**Expected Output:**
```
Taints:             <none>
Unschedulable:      false
```

**Key Indicators:**
- ✅ All nodes: Status `Ready`
- ✅ storagenodet3500: `Unschedulable: false` (not cordoned)
- ✅ masternode: `node-role.kubernetes.io/control-plane` taint present (normal)
- ✅ storagenodet3500: No taints (allows Jellyfin scheduling)

---

### 6) Readiness test from inside pod

**Command:**
```bash
POD=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pods -l app=blackbox-exporter -o name | head -n1)
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring exec -it $POD -- curl -sS -I http://127.0.0.1:9115/metrics
```

**Expected Output:**
```
HTTP/1.1 200 OK
Content-Type: text/plain; version=0.0.4; charset=utf-8
Date: Wed, 08 Oct 2025 19:38:00 GMT
```

**For Loki:**
```bash
POD=$(kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pods -l app=loki -o name | head -n1)
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring exec -it $POD -- curl -sS http://127.0.0.1:3100/ready
```

**Expected Output:**
```
ready
```

---

## Jellyfin Diagnostics

**Command:**
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n jellyfin get pods -o wide
```

**Expected Output:**
```
NAME       READY   STATUS    RESTARTS   AGE   IP           NODE               NOMINATED NODE   READINESS GATES
jellyfin   1/1     Running   0          30m   10.244.1.x   storagenodet3500   <none>           <none>
```

**Key Changes from Error Output:**
- ✅ Status: `Running` (was `Pending`)
- ✅ NODE: `storagenodet3500` (was `<none>`)

**Describe Jellyfin pod:**
```bash
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n jellyfin describe pod jellyfin
```

**Expected Key Sections:**
```yaml
Node:         storagenodet3500/192.168.4.61
Status:       Running
...
Node-Selectors:  kubernetes.io/hostname=storagenodet3500
Tolerations:     node.kubernetes.io/network-unavailable:NoExecute op=Exists for 300s
                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
...
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  30m   default-scheduler  Successfully assigned jellyfin/jellyfin to storagenodet3500
  Normal  Pulled     30m   kubelet            Container image "jellyfin/jellyfin:latest" already present on machine
  Normal  Created    30m   kubelet            Created container jellyfin
  Normal  Started    30m   kubelet            Started container jellyfin
```

**Key Indicators:**
- ✅ Node: `storagenodet3500` (matches nodeSelector)
- ✅ Status: `Running`
- ✅ Successfully scheduled
- ❌ No "nodes are available" or "unschedulable" errors

---

## Summary of Fixes Applied

| Issue | Root Cause | Fix | Verification |
|-------|------------|-----|--------------|
| Blackbox CrashLoopBackOff | `timeout` in wrong location | Moved to module level | Logs show "Loaded config file" |
| Loki CrashLoopBackOff | 168h period incompatible | Changed to 24h | Logs show "Loki started" |
| Jellyfin Pending | Node unschedulable | Added uncordon task | Pod Running on storagenodet3500 |

---

## Complete Verification Suite

Run all verification commands in sequence:

```bash
# 1. Check all pods
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring get pods -o wide
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n jellyfin get pods -o wide

# 2. Check logs (should have no errors)
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring logs deployment/blackbox-exporter --tail=50
kubectl --kubeconfig=/etc/kubernetes/admin.conf -n monitoring logs deployment/loki --tail=50

# 3. Test endpoints
NODE_IP=192.168.4.63
curl -I http://${NODE_IP}:9115/metrics  # Blackbox
curl http://${NODE_IP}:31100/ready      # Loki
curl -I http://192.168.4.61:30096/health # Jellyfin

# 4. Check node schedulability
kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes
# All should show "Ready" without "SchedulingDisabled"

# 5. Check for any error events
kubectl --kubeconfig=/etc/kubernetes/admin.conf get events -n monitoring --sort-by='.lastTimestamp' | grep -i error
kubectl --kubeconfig=/etc/kubernetes/admin.conf get events -n jellyfin --sort-by='.lastTimestamp' | grep -i error
```

**Expected**: All checks pass, no error events, all pods Running with 0 restarts.
