# Enterprise Monitoring and Infrastructure - Troubleshooting Guide

## Overview

This guide provides step-by-step troubleshooting procedures for the VMStation enterprise monitoring and infrastructure services.

## Table of Contents

1. [Time Synchronization Issues](#time-synchronization-issues)
2. [Prometheus Issues](#prometheus-issues)
3. [Loki Log Aggregation Issues](#loki-log-aggregation-issues)
4. [Syslog Server Issues](#syslog-server-issues)
5. [Grafana Dashboard Issues](#grafana-dashboard-issues)
6. [Kerberos/FreeIPA Issues](#kerberos-freeipa-issues)
7. [General Kubernetes Troubleshooting](#general-kubernetes-troubleshooting)

---

## Time Synchronization Issues

### Symptom: Log timestamps are inconsistent

**Root Cause:** Nodes have different system times due to clock drift.

**Diagnosis:**
```bash
# Run time sync validation
./tests/validate-time-sync.sh

# Check time on each node
kubectl exec -n infrastructure <chrony-pod> -c chrony -- date

# Check chrony tracking
kubectl exec -n infrastructure <chrony-pod> -c chrony -- chronyc tracking
```

**Solution:**
```bash
# Restart NTP pods
kubectl delete pods -n infrastructure -l app=chrony-ntp

# Wait for pods to restart
kubectl get pods -n infrastructure -l app=chrony-ntp -w

# Force time sync on system
sudo chronyc makestep

# Verify sync
chronyc tracking
```

### Symptom: NTP pod not syncing to upstream servers

**Diagnosis:**
```bash
# Check NTP sources
kubectl exec -n infrastructure <pod-name> -c chrony -- chronyc sources -v

# Check firewall/network
kubectl exec -n infrastructure <pod-name> -c chrony -- ping -c 3 time.google.com

# Check DNS resolution
kubectl exec -n infrastructure <pod-name> -c chrony -- nslookup time.google.com
```

**Solution:**
```bash
# If DNS fails, update chrony config to use IP addresses
# Edit ConfigMap:
kubectl edit configmap -n infrastructure chrony-config

# Change to:
# server 216.239.35.0 iburst  # time.google.com

# Restart pods
kubectl delete pods -n infrastructure -l app=chrony-ntp
```

### Symptom: High time offset (>1 second)

**Diagnosis:**
```bash
# Check system load
kubectl top nodes

# Check if chronyd is resource-starved
kubectl top pod -n infrastructure -l app=chrony-ntp

# Check logs for errors
kubectl logs -n infrastructure <pod-name> -c chrony --tail=100
```

**Solution:**
```bash
# Force immediate time adjustment
kubectl exec -n infrastructure <pod-name> -c chrony -- chronyc makestep

# Increase chronyd resource limits if needed
kubectl edit daemonset -n infrastructure chrony-ntp
# Update resources.limits.cpu and memory
```

---

## Prometheus Issues

### Symptom: Prometheus pod in CrashLoopBackOff

**Diagnosis:**
```bash
# Check pod events
kubectl describe pod -n monitoring prometheus-0

# Check logs
kubectl logs -n monitoring prometheus-0 --tail=100

# Check previous logs if pod restarted
kubectl logs -n monitoring prometheus-0 --previous
```

**Common Causes:**

1. **Invalid alert rules YAML syntax:**
If you see errors like "mapping values are not allowed in this context" in the logs, check for unquoted strings with colons in alert descriptions:
```bash
# Check logs for YAML syntax errors
kubectl logs -n monitoring prometheus-0 | grep "loading groups failed"

# The error typically shows the line number and column
# Common issue: unquoted descriptions with colons after template expressions
# Fix: Quote the description string
# WRONG: description: Server {{ $value }} (threshold: X)
# RIGHT: description: "Server {{ $value }} (threshold: X)"
```

2. **Invalid configuration:**
```bash
# Validate config
kubectl exec -n monitoring prometheus-0 -- promtool check config /etc/prometheus/prometheus.yml
```

3. **Permissions issue:**
```bash
# Check PVC permissions
kubectl exec -n monitoring prometheus-0 -- ls -la /prometheus

# Fix permissions (if needed)
kubectl delete pod -n monitoring prometheus-0
# Init container will fix permissions on restart
```

3. **Insufficient memory:**
```bash
# Check memory usage
kubectl top pod -n monitoring prometheus-0

# Increase memory limits
kubectl edit statefulset -n monitoring prometheus
```

### Symptom: Prometheus targets down

**Diagnosis:**
```bash
# List all targets
curl http://localhost:30090/api/v1/targets | jq '.data.activeTargets[] | select(.health!="up") | {job: .labels.job, instance: .labels.instance, health: .health}'

# Check specific target connectivity
kubectl exec -n monitoring prometheus-0 -- wget -O- http://node-exporter:9100/metrics
```

**Solution:**

1. **For pod targets:**
```bash
# Check if target pod is running
kubectl get pods -n <namespace> -l app=<target-app>

# Check if target port is exposed
kubectl get svc -n <namespace> <service-name>

# Test connectivity from Prometheus pod
kubectl exec -n monitoring prometheus-0 -- curl <target-service>:<port>/metrics
```

2. **For node exporters (host network):**
```bash
# SSH to node and check
ssh <node-ip>
systemctl status node_exporter
curl http://localhost:9100/metrics
```

### Symptom: Prometheus queries slow or timing out

**Diagnosis:**
```bash
# Check query stats
curl http://localhost:30090/api/v1/status/tsdb | jq

# Check cardinality
curl http://localhost:30090/api/v1/label/__name__/values | jq | wc -l

# Check resource usage
kubectl top pod -n monitoring prometheus-0
```

**Solution:**
```bash
# Increase query timeout and resources
kubectl edit statefulset -n monitoring prometheus

# Add/modify args:
- '--query.timeout=5m'
- '--query.max-concurrency=30'

# And increase resources:
resources:
  limits:
    cpu: 4000m
    memory: 8Gi
```

---

## Loki Log Aggregation Issues

### Symptom: Loki pod won't start (init container stuck)

**Diagnosis:**
```bash
# Check init container logs
kubectl logs -n monitoring loki-0 -c init-loki-data

# Check PVC status
kubectl get pvc -n monitoring loki-data-loki-0

# Check storage class
kubectl get storageclass
```

**Solution:**
```bash
# If PVC not binding, check storage provisioner
kubectl get pv

# Manually create PV if needed (for hostPath)
# Create loki-pv.yaml with matching storage

# Delete pod to retry
kubectl delete pod -n monitoring loki-0
```

### Symptom: Cannot query logs in Grafana

**Diagnosis:**
```bash
# Check Loki health
curl http://localhost:31100/ready

# Check if Loki is receiving logs
curl http://localhost:31100/metrics | grep loki_ingester_chunks_created_total

# Test query directly
curl -G http://localhost:31100/loki/api/v1/query --data-urlencode 'query={job="promtail"}' | jq
```

**Solution:**

1. **Loki not receiving logs:**
```bash
# Check Promtail is running
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail

# Check Promtail logs
kubectl logs -n monitoring <promtail-pod> --tail=100

# Verify Promtail can reach Loki
kubectl exec -n monitoring <promtail-pod> -- wget -O- http://loki:3100/ready
```

2. **Query syntax errors:**
```bash
# Use proper LogQL syntax
{job="promtail"}  # Valid
{namespace!="kube-system"}  # Invalid (empty matcher)
{job=~".+", namespace!="kube-system"}  # Valid
```

3. **Retention period issue:**
```bash
# Check retention settings
kubectl exec -n monitoring loki-0 -- cat /etc/loki/loki.yaml | grep retention

# Logs older than retention are deleted
# Default: 30 days (720h)
```

### Symptom: Loki high memory usage / OOMKilled

**Diagnosis:**
```bash
# Check memory usage
kubectl top pod -n monitoring loki-0

# Check WAL size
kubectl exec -n monitoring loki-0 -- du -sh /loki/wal

# Check number of streams
curl http://localhost:31100/metrics | grep loki_ingester_memory_streams
```

**Solution:**
```bash
# Increase memory limits
kubectl edit statefulset -n monitoring loki

# Reduce retention or ingestion rate limits
kubectl edit configmap -n monitoring loki-config

# In loki.yaml, modify:
limits_config:
  max_streams_per_user: 5000  # Reduce from 10000
  ingestion_rate_mb: 5  # Reduce from 10
```

---

## Syslog Server Issues

### Symptom: Syslog server not receiving logs

**Diagnosis:**
```bash
# Check syslog pod
kubectl get pods -n infrastructure -l app=syslog-server

# Check logs
kubectl logs -n infrastructure <syslog-pod> -c syslog-ng --tail=50

# Test UDP connectivity
echo "test" | nc -u -w1 <masternode-ip> 30514

# Test TCP connectivity
echo "test" | nc -w1 <masternode-ip> 30515
```

**Solution:**

1. **Firewall blocking:**
```bash
# Check firewall rules
sudo iptables -L -n | grep 30514

# Allow syslog ports
sudo iptables -A INPUT -p udp --dport 30514 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 30515 -j ACCEPT
```

2. **syslog-ng configuration error:**
```bash
# Check config syntax
kubectl exec -n infrastructure <syslog-pod> -c syslog-ng -- syslog-ng --syntax-only

# View config
kubectl get configmap -n infrastructure syslog-ng-config -o yaml
```

### Symptom: Syslog not forwarding to Loki

**Diagnosis:**
```bash
# Check Loki connectivity from syslog pod
kubectl exec -n infrastructure <syslog-pod> -c syslog-ng -- wget -O- http://loki.monitoring.svc.cluster.local:3100/ready

# Check syslog-ng logs for errors
kubectl logs -n infrastructure <syslog-pod> -c syslog-ng | grep -i error

# Check Loki ingestion metrics
curl http://localhost:31100/metrics | grep loki_distributor_bytes_received_total
```

**Solution:**
```bash
# Verify NetworkPolicy allows syslog → Loki
kubectl describe networkpolicy -n infrastructure syslog-server-netpol
kubectl describe networkpolicy -n monitoring loki-netpol

# Restart syslog pod
kubectl delete pod -n infrastructure <syslog-pod>
```

---

## Grafana Dashboard Issues

### Symptom: Dashboard shows "No Data"

**Diagnosis:**
```bash
# Check Grafana datasources
curl http://localhost:30300/api/datasources

# Test Prometheus datasource
curl http://localhost:30300/api/datasources/proxy/1/api/v1/query?query=up

# Test Loki datasource
curl http://localhost:30300/api/datasources/proxy/2/loki/api/v1/labels
```

**Solution:**

1. **Prometheus datasource:**
```bash
# Verify Prometheus is reachable from Grafana
kubectl exec -n monitoring <grafana-pod> -- wget -O- http://prometheus:9090/-/healthy

# Check if data exists
curl http://localhost:30090/api/v1/query?query=up
```

2. **Dashboard query syntax:**
```bash
# Prometheus queries use PromQL
up{job="node-exporter"}

# Loki queries use LogQL
{job="promtail", namespace="default"}
```

### Symptom: Cannot access Grafana UI

**Diagnosis:**
```bash
# Check Grafana pod
kubectl get pods -n monitoring -l app=grafana

# Check service
kubectl get svc -n monitoring grafana

# Test connection
curl http://localhost:30300/api/health
```

**Solution:**
```bash
# Restart Grafana
kubectl delete pod -n monitoring <grafana-pod>

# Check for CrashLoopBackOff
kubectl logs -n monitoring <grafana-pod> --tail=100

# If permission issues
kubectl delete pod -n monitoring <grafana-pod>
# Init container will fix permissions
```

---

## Kerberos/FreeIPA Issues

### Symptom: FreeIPA pod stuck in startup

**Diagnosis:**
```bash
# Check pod status
kubectl describe pod -n infrastructure freeipa-0

# Check logs
kubectl logs -n infrastructure freeipa-0 --tail=100

# Check resource usage
kubectl top pod -n infrastructure freeipa-0
```

**Solution:**

1. **Slow startup (normal for first install):**
```bash
# FreeIPA takes 5-10 minutes for initial setup
# Wait and monitor logs
kubectl logs -n infrastructure freeipa-0 -f
```

2. **Insufficient resources:**
```bash
# FreeIPA needs at least 2GB RAM, 1 CPU
kubectl edit statefulset -n infrastructure freeipa

# Increase resources if needed
```

3. **Data directory permissions:**
```bash
# Check init container logs
kubectl logs -n infrastructure freeipa-0 -c init-data

# Delete pod to retry
kubectl delete pod -n infrastructure freeipa-0
```

### Symptom: Cannot kinit (Kerberos authentication fails)

**Diagnosis:**
```bash
# Check if FreeIPA is ready
kubectl exec -n infrastructure freeipa-0 -- ipactl status

# Test Kerberos
echo "ChangeMe123!" | kinit admin@VMSTATION.LOCAL

# Check time sync (Kerberos very sensitive)
chronyc tracking
```

**Solution:**

1. **Time drift (most common):**
```bash
# Kerberos requires <5 minute time difference
# Fix time sync first
./tests/validate-time-sync.sh

# Force time sync
sudo chronyc makestep
```

2. **Wrong password or realm:**
```bash
# Verify admin password from secret
kubectl get secret -n infrastructure freeipa-secrets -o jsonpath='{.data.admin-password}' | base64 -d

# Use exact realm name
echo "<password>" | kinit admin@VMSTATION.LOCAL  # Not vmstation.local
```

---

## General Kubernetes Troubleshooting

### Pod Stuck in Pending

**Diagnosis:**
```bash
kubectl describe pod -n <namespace> <pod-name>
# Look for:
# - PVC not bound
# - Insufficient resources
# - Node selector not matching
```

**Solution:**
```bash
# Check PVC
kubectl get pvc -n <namespace>

# Check node resources
kubectl describe nodes | grep -A5 "Allocated resources"

# Check taints
kubectl describe nodes | grep Taints
```

### Pod in ImagePullBackOff

**Diagnosis:**
```bash
kubectl describe pod -n <namespace> <pod-name>
# Look for:
# - Image name typo
# - Private registry authentication
# - Network issues
```

**Solution:**
```bash
# Pull image manually to verify
docker pull <image:tag>

# Check image pull secrets
kubectl get secrets -n <namespace>
```

### NetworkPolicy Blocking Traffic

**Diagnosis:**
```bash
# List all NetworkPolicies
kubectl get networkpolicies -A

# Describe specific policy
kubectl describe networkpolicy -n <namespace> <policy-name>

# Test connectivity
kubectl exec -n <namespace> <pod-name> -- curl <target-service>
```

**Solution:**
```bash
# Temporarily disable for testing
kubectl delete networkpolicy -n <namespace> <policy-name>

# If traffic works, update policy rules
kubectl edit networkpolicy -n <namespace> <policy-name>
```

---

## Quick Reference Commands

```bash
# Get all resources in namespace
kubectl get all -n <namespace>

# Check pod logs
kubectl logs -n <namespace> <pod-name> --tail=100 -f

# Describe pod (events, status)
kubectl describe pod -n <namespace> <pod-name>

# Get into pod shell
kubectl exec -n <namespace> <pod-name> -it -- /bin/sh

# Check resource usage
kubectl top nodes
kubectl top pods -n <namespace>

# Force pod restart
kubectl delete pod -n <namespace> <pod-name>

# Check persistent volumes
kubectl get pv,pvc -A

# View cluster events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

---

## Support and Documentation

- **Validation Scripts:** `tests/validate-time-sync.sh`
- **Deployment Docs:** `docs/*_ENTERPRISE_REWRITE.md`
- **Playbooks:** `ansible/playbooks/deploy-*.yaml`
- **Manifests:** `manifests/monitoring/`, `manifests/infrastructure/`

For additional help, check pod logs and Kubernetes events first, then consult the relevant documentation for your component.
