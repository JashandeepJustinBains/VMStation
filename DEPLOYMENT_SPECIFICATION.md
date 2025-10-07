# VMStation Kubernetes Homelab Deployment Specification

## Executive Summary

VMStation is a comprehensive Kubernetes homelab deployment automation system designed for a mixed-architecture environment consisting of Debian Bookworm nodes (using kubeadm) and RHEL 10 nodes (using RKE2). The system provides bulletproof, idempotent deployment capabilities with robust error handling, comprehensive logging, and zero-touch automation.

## Architecture Overview

### Deployment Strategy
- **Two-Phase Deployment**: Separate but coordinated deployment of Debian-based kubeadm cluster and RKE2 cluster
- **Clean Separation**: No mixing of kubeadm and RKE2 nodes within the same cluster
- **Idempotent Operations**: All deployment operations must work repeatedly without manual intervention
- **Zero-Touch Automation**: Complete automation with comprehensive error recovery and diagnostics

### Infrastructure Components

#### Debian Cluster (kubeadm-based)
- **Control Plane**: masternode (192.168.4.63) - Kubernetes control-plane with monitoring services
- **Worker Nodes**: storagenodet3500 (192.168.4.61) - Storage and media services
- **Technology Stack**: kubeadm v1.29.x, containerd runtime, Flannel CNI

#### RKE2 Cluster (Rancher Kubernetes Engine 2)
- **Single Node**: homelab (192.168.4.62) - Compute workloads and monitoring federation
- **Technology Stack**: RKE2 v1.29.x, integrated container runtime, Flannel CNI

### Network Architecture
- **Subnet**: 192.168.4.0/24
- **API Server**: Port 6443 (Kubernetes API)
- **Node Communication**: Standard Kubernetes networking
- **Service Discovery**: CoreDNS
- **CNI**: Flannel with VXLAN backend

## Deployment Phases

### Phase 0: System Preparation
**Target**: All nodes (monitoring_nodes, storage_nodes, compute_nodes)
**Objectives**:
- Install all required apps/programs/librairees necessary on all debian machines such as Kubernetes binaries (kubelet, kubeadm, kubectl)
- Configure containerd runtime
- Set up systemd services
- Validate system prerequisites
- Ensure proper RBAC configuration

**Key Requirements**:
- Robust containerd installation with fallback package names
- Service unit file validation and auto-repair
- Admin kubeconfig generation with correct RBAC (O=system:masters)
- OS-specific handling (Debian vs RHEL differences)

### Phase 1: Control Plane Initialization
**Target**: monitoring_nodes (masternode)
**Objectives**:
- Initialize Kubernetes control plane with kubeadm
- Generate bootstrap tokens for worker joins
- Configure admin certificates
- Validate control plane health

**Key Requirements**:
- Idempotent initialization (handle existing clusters)
- Proper certificate authority setup
- Token generation with appropriate permissions
- Control plane service validation

### Phase 2: Control Plane Validation
**Target**: monitoring_nodes (masternode)
**Objectives**:
- Verify control plane components are running
- Test API server accessibility
- Validate certificate configuration
- Prepare for worker node joins

**Critical Implementation Details**:
- **Container Runtime Check**: Verify kube-apiserver, kube-controller-manager, kube-scheduler, etcd containers are running
- **Systemd Fallback**: Check kubelet and containerd services if container check fails
- **API Server Health**: Test HTTPS connectivity to port 6443
- **Cluster Connectivity**: Verify kubectl can communicate with the cluster
- **Multi-Method Validation**: Use both container inspection and systemd status checks for robustness

### Phase 3: Token Generation
**Target**: monitoring_nodes (masternode)
**Objectives**:
- Generate fresh join tokens
- Create discovery tokens for worker authentication
- Set appropriate token expiration times

### Phase 4: Worker Node Join (Critical Phase)
**Target**: storage_nodes, compute_nodes (Debian nodes only)
**Objectives**:
- Join worker nodes to kubeadm cluster
- Handle all edge cases and failure scenarios
- Provide comprehensive diagnostics

**Critical Requirements**:
- **Idempotent Behavior**: Check existing join status, skip if already joined
- **Pre-Join Cleanup**: Kill hanging processes, remove partial state, ensure clean directories
- **Robust Prerequisites**: Containerd socket validation, kubeadm binary verification, control plane connectivity
- **Retry Logic**: Multiple attempts with exponential backoff
- **Comprehensive Logging**: Success logs and detailed failure diagnostics
- **Health Validation**: Kubelet service startup, config file creation, service health monitoring
- **Error Recovery**: Automatic capture of system state, service status, network connectivity

### Phase 5: CNI Deployment
**Target**: All cluster nodes
**Objectives**:
- Deploy Flannel CNI plugin
- Configure pod networking
- Validate network connectivity
- Ensure proper subnet allocation

### Phase 6: Cluster Validation
**Target**: monitoring_nodes
**Objectives**:
- Verify all nodes are Ready
- Check core system pods (kube-proxy, coredns, etc.)
- Validate CNI functionality
- Test basic cluster operations

### Phase 7: Application Deployment
**Objectives**:
- Deploy monitoring stack (Prometheus, Grafana, Loki)
- Deploy application services (Jellyfin, etc.)
- Configure ingress and load balancing
- Set up backup and recovery

**Monitoring Stack Components**:
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation and querying
- **Node Exporter**: System metrics collection
- **Kube State Metrics**: Kubernetes object metrics

## Monitoring and Logging Configuration

### Prometheus Configuration
**Deployment**: `manifests/monitoring/prometheus.yaml`
**Key Features**:
- ClusterRole with appropriate permissions for metrics collection
- ServiceAccount for secure access
- ConfigMap for scrape configurations
- ServiceMonitor for automatic target discovery

**Scrape Configurations**:
```yaml
# Kubernetes API server metrics
- job_name: 'kubernetes-apiservers'
  kubernetes_sd_configs:
  - role: endpoints
  scheme: https
  tls_config:
    ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
  relabel_configs:
  - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name]
    action: keep
    regex: default;kubernetes

# Node metrics via kubelet
- job_name: 'kubernetes-nodes'
  scheme: https
  tls_config:
    ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
  bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
  kubernetes_sd_configs:
  - role: node
  relabel_configs:
  - action: labelmap
    regex: __meta_kubernetes_node_label_(.+)
```

### Grafana Configuration
**Deployment**: `manifests/monitoring/grafana.yaml`
**Key Features**:
- Pre-configured datasources (Prometheus, Loki)
- Dashboard providers for automatic dashboard loading
- Admin user configuration
- Persistent volume for dashboard storage

**Datasources Configuration**:
```yaml
apiVersion: 1
datasources:
- name: Prometheus
  type: prometheus
  access: proxy
  url: http://prometheus:9090
  isDefault: true
  editable: true
- name: Loki
  type: loki
  access: proxy
  url: http://loki:3100
  editable: true
```

**Dashboards**:
- **Kubernetes Cluster Overview**: Node status, pod health, resource usage
- **Node Metrics**: CPU, memory, disk, network per node
- **Prometheus Metrics**: Scrape targets, query performance
- **Loki Logs**: Log aggregation and search interface

### Loki Log Aggregation
**Purpose**: Centralized logging for all cluster components
**Configuration**:
- Ingests logs from all pods and nodes
- Provides query interface for log analysis
- Integrates with Grafana for log visualization
- Supports log-based alerting

**Log Sources**:
- Kubernetes system component logs
- Application container logs
- Node system logs
- Audit logs

### Node Exporter Configuration
**Deployment**: Automatic via DaemonSet
**Metrics Collected**:
- CPU usage and utilization
- Memory usage and swap
- Disk I/O and space
- Network interface statistics
- System load and uptime
- Hardware sensors (temperature, fan speed)

### Kube State Metrics
**Purpose**: Expose detailed Kubernetes object metrics
**Metrics Include**:
- Pod status and lifecycle
- Deployment rollout status
- Service endpoint counts
- Persistent volume claims
- Node capacity and allocation
- Resource quota usage

### Alerting Rules
**Prometheus Alerting**:
```yaml
groups:
- name: kubernetes-apps
  rules:
  - alert: KubePodCrashLooping
    expr: rate(kube_pod_container_status_restarts_total[10m]) > 0
    for: 1m
    labels:
      severity: warning
    annotations:
      summary: Pod {{ $labels.pod }} is crash looping
      description: Pod {{ $labels.pod }} is restarting {{ $value }} times / 10 min.

  - alert: KubeNodeNotReady
    expr: kube_node_status_condition{condition="Ready",status="true"} == 0
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: Node {{ $labels.node }} is not ready
      description: Node {{ $labels.node }} has been unready for more than 5 minutes.
```

### Log Aggregation Patterns
**Application Logs**:
- Structured logging with consistent format
- Log levels: DEBUG, INFO, WARN, ERROR
- Contextual information (pod name, namespace, timestamp)
- Correlation IDs for request tracing

**System Logs**:
- Kubernetes component logs via journald
- Node system logs collection
- Audit logs for security events
- Container runtime logs

### Monitoring Dashboards
**Main Dashboard (Kubernetes Overview)**:
- Cluster health status
- Node resource utilization
- Pod status distribution
- Network traffic metrics
- API server performance

**Node Details Dashboard**:
- Per-node CPU/memory/disk metrics
- Network interface statistics
- System load and processes
- Container runtime metrics

**Application Monitoring**:
- Service response times
- Error rates and patterns
- Resource usage by application
- Custom business metrics

## Technical Specifications

### Software Versions
- **Ansible**: Core 2.14.18+ (Python 3.11+)
- **Kubernetes**: v1.29.15 (server), v1.34.0 (client)
- **Containerd**: v1.7.28-1
- **Flannel**: v0.27.4
- **RKE2**: v1.29.x (latest stable)

### Operating System Requirements

#### Debian Bookworm Nodes
- **Firewall**: iptables backend
- **Systemd**: Full systemd support required
- **Package Management**: apt with hold packages for version stability
- **Authentication**: Root SSH access

#### RHEL 10 Nodes
- **Firewall**: nftables backend
- **Systemd**: Full systemd support required
- **Package Management**: dnf/yum
- **Authentication**: Sudo with vault-encrypted passwords

### Container Runtime Configuration
- **Runtime**: containerd
- **SystemdCgroup**: true
- **Socket Path**: /var/run/containerd/containerd.sock
- **Registry Configuration**: Allow insecure registries if needed

### Kubernetes Configuration
- **Pod CIDR**: 10.244.0.0/16 (Flannel default)
- **Service CIDR**: 10.96.0.0/12
- **DNS Domain**: cluster.local
- **RBAC**: Enabled with proper admin certificates
- **Monitoring Namespace**: Dedicated `monitoring` namespace for all observability components
- **Resource Limits**: Configured for monitoring workloads to prevent resource exhaustion

## Implementation Requirements

### Idempotency Standards
- **Zero Failures**: `deploy.sh` → `deploy.sh reset` → `deploy.sh` must work 100 times consecutively
- **State Awareness**: All operations must check current state before making changes
- **Clean Recovery**: Handle partial states, hanging processes, and corrupted configurations
- **Reboot Resilience**: Deployment must work after system reboots without manual intervention

### Error Handling and Diagnostics
- **Comprehensive Logging**: All operations logged with timestamps and context
- **Failure Diagnostics**: Automatic capture of system state on failures
- **Retry Mechanisms**: Exponential backoff with configurable limits
- **Graceful Degradation**: Continue with available resources when possible

### Security Considerations
- **Certificate Management**: Proper CA setup and certificate rotation
- **RBAC Configuration**: Correct admin user permissions (O=system:masters)
- **Monitoring RBAC**: Dedicated service accounts for Prometheus with minimal required permissions
- **Network Security**: Appropriate firewall rules for Kubernetes networking
- **Secret Management**: Ansible vault for sensitive credentials
- **Log Security**: Secure log transport and access controls

## Critical Implementation Details

### Containerd Installation Robustness
```yaml
# Try multiple package names with fallback logic
- name: Install containerd
  package:
    name: "{{ item }}"
    state: present
  loop:
    - containerd.io
    - containerd
  when: not containerd_installed.stat.exists
```

### Worker Join Idempotency
```yaml
# Check existing join status
- name: Check if node already joined
  stat:
    path: /etc/kubernetes/kubelet.conf
  register: kubelet_conf

# Skip if already joined
- name: Skip join if already joined
  when: kubelet_conf.stat.exists
  debug:
    msg: "{{ inventory_hostname }} already joined"
```

### Process Cleanup Logic
```bash
# Kill hanging processes gracefully then forcefully
pkill -f "kubeadm join" || true
sleep 2
pkill -9 -f "kubeadm join" || true
```

### Health Validation
```yaml
# Wait for kubelet config with timeout
- name: Wait for kubelet config
  wait_for:
    path: /etc/kubernetes/kubelet.conf
    timeout: 120

# Validate kubelet health
- name: Check kubelet service health
  systemd:
    name: kubelet
    state: started
  register: kubelet_status
```

## Troubleshooting Knowledge Base

### Common Failure Patterns
1. **Containerd Socket Missing**: Enhanced installation with multiple package attempts
2. **Admin Kubeconfig RBAC Issues**: Automated regeneration with correct subject
3. **Worker Join Hanging**: Comprehensive cleanup and retry logic
4. **Kubelet Crash Loops**: Config file validation and service health checks
5. **Partial Join States**: Thorough artifact cleanup before retry attempts
6. **Control Plane Validation Hanging**: Incorrect pod label checks - use container runtime inspection instead

### Diagnostic Commands
```bash
# Service status checks
systemctl status containerd kubelet

# Control plane container inspection
docker ps | grep kube-apiserver
ctr -n k8s.io containers ls | grep kube

# API server connectivity
curl -k https://localhost:6443/healthz

# Cluster connectivity test
kubectl cluster-info --kubeconfig=/etc/kubernetes/admin.conf

# Log inspection
journalctl -u kubelet -n 50 --no-pager
journalctl -u containerd -n 50 --no-pager

# Process monitoring
ps aux | grep kubeadm
ss -tlnp | grep -E '6443|10250'

# File system validation
ls -la /var/lib/kubelet/ /etc/kubernetes/
```

### Log Locations
- **Join Success**: `/var/log/kubeadm-join.log`
- **Join Failures**: `/var/log/kubeadm-join-failure.log`
- **System Logs**: `journalctl -u kubelet`, `journalctl -u containerd`

## Deployment Workflow

### Primary Deployment Command
```bash
./deploy.sh all --with-rke2 --yes
```

### Reset Command
```bash
./deploy.sh reset
```

### Test Commands
```bash
# Syntax validation
ansible-playbook --syntax-check playbooks/deploy-cluster.yaml

# Dry run
ansible-playbook --check playbooks/deploy-cluster.yaml

# Idempotency testing
for i in {1..10}; do ./deploy.sh all --with-rke2 --yes; done
```

## Quality Assurance Requirements

### Testing Standards
- **Unit Tests**: Individual role and task validation
- **Integration Tests**: End-to-end deployment verification
- **Idempotency Tests**: Repeated deployment validation
- **Failure Recovery Tests**: Chaos engineering and error injection

### Validation Checkpoints
1. All nodes report Ready status
2. CoreDNS and kube-proxy pods running
3. CNI networking functional
4. API server accessible
5. Worker nodes properly joined
6. RBAC permissions correct
7. Certificate validity confirmed

## Future Considerations

### Scalability
- Support for additional worker nodes
- Multi-master high availability
- Load balancer integration

### Security Enhancements
- Certificate rotation automation
- Network policy implementation
- Secret management improvements

### Advanced Monitoring
- Distributed tracing (Jaeger/OpenTelemetry)
- Application performance monitoring
- Custom metrics exporters
- Log retention and archiving policies

## Deployment Manifests and Configurations

### Monitoring Stack Files
- **Prometheus**: `manifests/monitoring/prometheus.yaml`
  - ServiceAccount, ClusterRole, ClusterRoleBinding
  - Deployment with persistent volume
  - Service and ConfigMap for scrape configurations
- **Grafana**: `manifests/monitoring/grafana.yaml`
  - ConfigMaps for datasources and dashboard providers
  - Deployment with admin configuration
  - Service for web access
- **Grafana Datasources**: `ansible/files/grafana_datasources/prometheus-datasource.yaml`
- **Grafana Dashboards**: `ansible/files/grafana_dashboards/`
  - `node-dashboard.json`: Node-level metrics
  - `prometheus-dashboard.json`: Prometheus performance
  - `loki-dashboard.json`: Log aggregation interface

### Application Deployment Structure
- **Jellyfin**: `manifests/jellyfin/` and `ansible/plays/jellyfin.yml`
- **Network Policies**: `manifests/network/`
- **CNI Configuration**: `manifests/cni/flannel.yaml`

### Ansible Integration
- **Monitoring Deployment**: Integrated into Phase 7 application deployment
- **Dashboard Provisioning**: Automated via Ansible file copy operations
- **Configuration Management**: Templated configurations for environment-specific settings