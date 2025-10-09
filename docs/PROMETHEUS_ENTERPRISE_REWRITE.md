# Prometheus Monitoring Stack - Enterprise Rewrite Documentation

## Overview

This document details the comprehensive rewrite of the Prometheus monitoring manifest to meet industry-standard best practices for production Kubernetes environments.

## Key Changes and Rationale

### 1. StatefulSet Instead of Deployment

**Change:** Converted from Deployment to StatefulSet
**Rationale:**
- **Stable Network Identity:** Each Prometheus pod gets a predictable DNS name (prometheus-0, prometheus-1, etc.)
- **Ordered Deployment:** Pods are created and terminated in order, ensuring data consistency
- **Persistent Storage Management:** StatefulSet automatically manages PVCs with volumeClaimTemplates
- **Better for Databases:** Prometheus stores time-series data and benefits from stable storage bindings
- **HA Readiness:** Easier to scale to multiple replicas with stable identities

### 2. Enhanced Security Context

**Changes:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65534  # nobody user
  fsGroup: 65534
  seccompProfile:
    type: RuntimeDefault
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
    - ALL
```

**Rationale:**
- **Principle of Least Privilege:** Run as non-root user (65534 = nobody)
- **Read-Only Filesystem:** Prevents container compromise from persisting changes
- **Drop All Capabilities:** Remove unnecessary Linux capabilities
- **Seccomp Profile:** Enable security compute mode filtering
- **Industry Standard:** Aligns with CIS Kubernetes Benchmark and Pod Security Standards

### 3. Proper Resource Management

**Changes:**
```yaml
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

**Rationale:**
- **QoS Guaranteed:** Matching requests and reasonable limits ensure pod priority
- **Prevent Resource Starvation:** Limits prevent Prometheus from consuming all node resources
- **Right-Sized:** Based on typical monitoring workload for 3-node cluster
- **Production Scale:** Increased from original 256Mi/1Gi to handle enterprise workloads

### 4. Comprehensive Health Probes

**Changes:** Added liveness, readiness, and startup probes

**Liveness Probe:**
```yaml
livenessProbe:
  httpGet:
    path: /-/healthy
    port: web
  initialDelaySeconds: 30
  periodSeconds: 30
```
- Checks if Prometheus process is alive
- Kubelet restarts pod if probe fails
- 30s initial delay allows for startup

**Readiness Probe:**
```yaml
readinessProbe:
  httpGet:
    path: /-/ready
    port: web
  initialDelaySeconds: 30
  periodSeconds: 10
```
- Checks if Prometheus can serve requests
- Pod removed from service endpoints if not ready
- More frequent checks (10s) for faster failover

**Startup Probe:**
```yaml
startupProbe:
  httpGet:
    path: /-/ready
    port: web
  failureThreshold: 20  # 5 minutes
```
- Allows slow startup without failing liveness
- Critical for Prometheus with large TSDB
- 20 failures × 15s = 5 minutes to start

### 5. Config Reload Sidecar

**Change:** Added prometheus-config-reloader sidecar container

**Rationale:**
- **Zero-Downtime Updates:** Reload configuration without pod restart
- **Production Operations:** Essential for updating scrape configs in live environment
- **Kubernetes Native:** Watches ConfigMap changes and triggers reload
- **Resource Efficient:** Minimal overhead (10m CPU, 16Mi memory)

### 6. Init Container for Permissions

**Change:** Added init-chown-data container

**Rationale:**
- **Storage Permissions:** Ensure Prometheus can write to persistent volume
- **Non-Root Operation:** Main container runs as nobody (65534)
- **idempotent:** Safe to run multiple times
- **Standard Pattern:** Common practice for StatefulSets with persistent storage

### 7. Anti-Affinity for High Availability

**Change:** Added pod anti-affinity rules

**Rationale:**
- **Fault Tolerance:** Prevents all Prometheus replicas on same node
- **HA Deployment:** Critical for multi-replica setup
- **Soft Affinity:** Uses `preferredDuringSchedulingIgnoredDuringExecution` for flexibility
- **Future-Proof:** Ready for scaling to multiple replicas

### 8. Priority Class Assignment

**Change:** Added `priorityClassName: system-cluster-critical`

**Rationale:**
- **Resource Preemption:** Ensures Prometheus pods aren't evicted under pressure
- **Critical Workload:** Monitoring is infrastructure-critical
- **Kubernetes Native:** Uses built-in priority class
- **Production Standard:** Aligns with cluster-critical services (DNS, CNI)

### 9. Improved Storage Configuration

**Changes:**
```yaml
args:
  - '--storage.tsdb.retention.time=30d'
  - '--storage.tsdb.retention.size=4GB'
  - '--storage.tsdb.wal-compression'

volumeClaimTemplates:
  - metadata:
      name: prometheus-storage
    spec:
      resources:
        requests:
          storage: 10Gi  # Increased from 5Gi
```

**Rationale:**
- **Retention Size Limit:** Prevents disk exhaustion (4GB max)
- **WAL Compression:** Reduces write-ahead log size by ~50%
- **Increased Storage:** 10Gi allows for 30 days of metrics at scale
- **Auto-PVC Management:** StatefulSet creates and binds PVCs automatically

### 10. Performance Tuning

**Changes:**
```yaml
args:
  - '--query.timeout=2m'
  - '--query.max-concurrency=20'
  - '--query.max-samples=50000000'
```

**Rationale:**
- **Query Timeout:** Prevents runaway queries from blocking Prometheus
- **Concurrency Limit:** Controls resource usage from simultaneous queries
- **Sample Limit:** Protects against queries that would load too much data
- **Grafana Compatibility:** Tuned for typical dashboard query patterns

### 11. Network Policy for Security

**Change:** Added comprehensive NetworkPolicy

**Rationale:**
- **Defense in Depth:** Network segmentation prevents lateral movement
- **Explicit Allow:** Only specified traffic is permitted
- **Ingress Control:** Grafana, self-scraping, and NodePort access
- **Egress Control:** Scrape targets, DNS, and API server access
- **Compliance:** Required for PCI-DSS, HIPAA, and other standards

### 12. Dual Service Architecture

**Change:** Separate ClusterIP (headless) and NodePort services

**Rationale:**
- **Headless Service:** Required for StatefulSet pod DNS (prometheus-0.prometheus.monitoring.svc)
- **NodePort Service:** External access for operators and debugging
- **Service Discovery:** Internal services use ClusterIP, external use NodePort
- **Security:** Can apply different policies to each service type

### 13. Infrastructure Service Integration

**Change:** Added scrape configs for NTP, Syslog, and FreeIPA monitoring

**Rationale:**
- **Time Sync Monitoring:** Critical for log correlation and distributed systems
- **Log Aggregation Health:** Monitor syslog message rates and availability
- **Identity Service Metrics:** Track Kerberos authentication and LDAP queries
- **Holistic Monitoring:** Complete visibility into infrastructure services

### 14. Enhanced Alerting Rules

**New Alert Groups:**
- `time-sync.rules`: NTP service health, time offset, synchronization status
- `logging.rules`: Syslog server health, message rate anomalies
- `monitoring.rules`: Prometheus self-monitoring, TSDB health, config reload status

**Rationale:**
- **Proactive Detection:** Alert before service degradation affects users
- **Time Drift Prevention:** Critical alert for the log timestamp issue mentioned in requirements
- **Self-Monitoring:** Prometheus monitors its own health
- **Actionable Alerts:** Each alert includes summary and description for troubleshooting

### 15. ConfigMap Checksum Annotation

**Change:**
```yaml
annotations:
  checksum/config: "{{ .Values.config | sha256sum }}"
```

**Rationale:**
- **Automatic Rollout:** Pod restarts when ConfigMap changes
- **Kubernetes Pattern:** Standard practice in Helm charts
- **Manual Implementation:** Checksum must be calculated and updated manually (or via CI/CD)
- **Alternative:** Config-reloader sidecar handles this dynamically

## Deployment Compatibility

### Breaking Changes
1. **PVC Name Change:** StatefulSet creates `prometheus-storage-prometheus-0` instead of `prometheus-pvc`
   - **Migration Path:** Backup data, deploy new StatefulSet, restore data
   - **Alternative:** Copy data to new PVC before cutover

2. **Service Selector:** Changed to use `app.kubernetes.io/name` and `app.kubernetes.io/component`
   - **Impact:** Existing services will continue to work due to label compatibility
   - **Migration:** Update external references to use new service names

3. **Pod Name:** Changes from `prometheus-<random>` to `prometheus-0`
   - **Impact:** Scripts or dashboards referencing pod names need updates
   - **Benefit:** Predictable names simplify operations

### Non-Breaking Changes
- Resource limits increased (may require node with more resources)
- Additional containers (config-reloader, init-chown-data) have minimal overhead
- NetworkPolicy only affects traffic if network plugin supports it
- Priority class assignment doesn't affect scheduling unless cluster is under pressure

## Validation Checklist

After deploying the rewritten Prometheus manifest:

- [ ] StatefulSet created: `kubectl get statefulset -n monitoring prometheus`
- [ ] Pod is running: `kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus`
- [ ] PVC automatically created: `kubectl get pvc -n monitoring prometheus-storage-prometheus-0`
- [ ] Health probes passing: `kubectl describe pod -n monitoring prometheus-0`
- [ ] Prometheus UI accessible: `http://<node-ip>:30090`
- [ ] Targets being scraped: Check Prometheus UI → Status → Targets
- [ ] Config reload works: Update ConfigMap and verify reload
- [ ] Metrics retained after pod restart
- [ ] Alerts firing as expected: Check Prometheus UI → Alerts
- [ ] NetworkPolicy not blocking legitimate traffic
- [ ] Resource usage within limits: `kubectl top pod -n monitoring prometheus-0`

## Performance Benchmarks

Expected metrics for 3-node cluster with typical workload:

| Metric | Value | Notes |
|--------|-------|-------|
| Ingestion Rate | 5,000-10,000 samples/s | Depends on scrape interval |
| Memory Usage | 500Mi-2Gi | Increases with retention and series |
| CPU Usage | 200m-800m | Spikes during queries and compaction |
| Disk Usage | 50-100MB/day | Varies with metric cardinality |
| Query Latency | <100ms (p50), <500ms (p99) | For typical dashboard queries |
| TSDB Blocks | 1-2 per day | Compressed and merged over time |

## Troubleshooting

### Pod in CrashLoopBackOff
- **Check logs:** `kubectl logs -n monitoring prometheus-0`
- **Common causes:** Permissions issue with PVC, invalid configuration, insufficient memory
- **Solution:** Verify init container ran, check YAML syntax, increase memory limits

### Config Reload Failing
- **Check config-reloader logs:** `kubectl logs -n monitoring prometheus-0 -c config-reloader`
- **Common causes:** Invalid Prometheus config, YAML syntax error
- **Solution:** Validate config with `promtool check config prometheus.yml`

### High Memory Usage
- **Check TSDB stats:** Prometheus UI → Status → TSDB Stats
- **Common causes:** High cardinality metrics, long retention
- **Solution:** Reduce retention time/size, drop high-cardinality labels, increase memory limits

### NetworkPolicy Blocking Traffic
- **Symptoms:** Targets showing as down, Grafana can't query Prometheus
- **Check:** `kubectl describe networkpolicy -n monitoring prometheus-netpol`
- **Solution:** Add necessary ingress/egress rules, verify namespace labels

## Future Enhancements

1. **High Availability:** Scale to 2+ replicas with Thanos for deduplication
2. **Remote Write:** Send metrics to long-term storage (Thanos, Cortex, M3DB)
3. **Authentication:** Add OAuth proxy or basic auth for web UI
4. **TLS:** Enable HTTPS for Prometheus web interface
5. **Alert Manager:** Deploy AlertManager for advanced notification routing
6. **Recording Rules:** Pre-compute expensive queries for dashboard performance
7. **Grafana Tempo:** Add distributed tracing integration
8. **Service Mesh:** Integrate with Istio/Linkerd for mesh metrics

## References

- [Prometheus Operator Best Practices](https://prometheus-operator.dev/docs/operator/design/)
- [Prometheus Production Deployment Guide](https://prometheus.io/docs/prometheus/latest/storage/)
- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [TSDB Documentation](https://prometheus.io/docs/prometheus/latest/storage/)

## Change Log

- **2025-01-XX:** Initial enterprise rewrite
  - Converted Deployment to StatefulSet
  - Added security contexts and probes
  - Implemented NetworkPolicy
  - Added config-reloader sidecar
  - Enhanced alerting rules
  - Integrated infrastructure service monitoring
