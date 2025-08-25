# Red Hat Quay Integration for VMStation

This document explains how to integrate Red Hat Quay container registry with your VMStation homelab project, including free usage options and Prometheus metrics integration.

## Overview

Red Hat Quay provides enterprise-grade container registry capabilities with Prometheus-compatible metrics endpoints, making it an excellent complement to your existing VMStation monitoring stack.

## Free Usage Options

### 1. Quay.io Free Tier
- **Cost**: Free for public repositories
- **Limits**: Unlimited public repositories, limited private repositories
- **Best for**: Open source projects, learning, and public container images
- **URL**: https://quay.io

### 2. Red Hat Developer Program
- **Cost**: Free with Red Hat Developer account
- **Includes**: Access to Red Hat Container Catalog and some Quay features
- **Best for**: Development and testing environments
- **Registration**: https://developers.redhat.com

## Current VMStation Setup Analysis

Your VMStation project currently uses:
- **Local Registry**: 192.168.4.63:5000 (insecure, internal only)
- **Image Sources**: docker.io, quay.io/podman/stable:latest
- **Monitoring**: Prometheus + Grafana stack
- **Container Runtime**: Podman

## Integration Scenarios

### Scenario 1: Hybrid Approach (Recommended)
Keep your local registry for private/development images and use Quay.io for:
- Public images you want to share
- Backup/mirror of critical images
- Images that benefit from Quay's security scanning

### Scenario 2: Full Migration
Replace local registry with Quay.io for all images (requires private repo subscription for sensitive images).

### Scenario 3: Metrics Only
Keep current setup but add Quay metrics monitoring to your Prometheus stack.

## Prometheus Metrics Integration

Red Hat Quay exports Prometheus-compatible metrics on `/metrics` endpoint. Here's how to integrate:

### 1. Add Quay Metrics to Prometheus Configuration

Update your `ansible/templates/prometheus.yml.j2`:

```yaml
scrape_configs:
  # Existing configs...
  
  - job_name: 'quay_metrics'
    static_configs:
      - targets: ['quay.io']  # Or your self-hosted Quay instance
    metrics_path: '/metrics'
    scheme: https
    scrape_interval: 30s
    scrape_timeout: 10s
```

### 2. Available Quay Metrics

Quay provides metrics for:
- Repository operations (push/pull counts)
- Build system metrics
- Storage usage
- Authentication events
- Security scan results
- Garbage collection stats

Example metrics:
```
quay_repository_pulls_total
quay_repository_pushes_total
quay_build_requests_total
quay_storage_usage_bytes
quay_security_scans_total
```

## Configuration Examples

### 1. Using Quay.io as Additional Registry

Update your container registry configuration in `ansible/plays/monitoring/publish_local_registry.yml`:

```yaml
- name: Configure multiple registries including Quay
  hosts: all
  become: true
  tasks:
    - name: Update registries configuration for Quay access
      copy:
        dest: /etc/containers/registries.conf.d/quay-registry.conf
        content: |
          unqualified-search-registries = ["docker.io", "quay.io"]
          
          # Local registry (keep existing)
          [[registry]]
          prefix = "192.168.4.63:5000"
          location = "192.168.4.63:5000"
          insecure = true
          
          # Quay.io registry
          [[registry]]
          prefix = "quay.io"
          location = "quay.io"
          
          # Red Hat registry
          [[registry]]
          prefix = "registry.redhat.io"
          location = "registry.redhat.io"
        owner: root
        group: root
        mode: '0644'
```

### 2. Ansible Playbook for Quay Authentication

Create `ansible/plays/setup_quay_auth.yaml`:

```yaml
---
- name: Setup Quay.io authentication
  hosts: all
  become: true
  vars_files:
    - ../group_vars/all.yml  # Contains Quay credentials
  tasks:
    - name: Login to Quay.io registry
      containers.podman.podman_login:
        registry: quay.io
        username: "{{ quay_username }}"
        password: "{{ quay_password }}"
      when: quay_username is defined and quay_password is defined
```

### 3. Update Existing Image References

Modify `ansible/plays/monitoring/publish_local_registry.yml` to use Quay as fallback:

```yaml
- name: Pull image with fallback to Quay
  block:
    - name: Try pulling from local registry first
      command: podman pull 192.168.4.63:5000/podman-system-metrics:latest
      register: local_pull
  rescue:
    - name: Fallback to Quay.io
      command: podman pull quay.io/your-org/podman-system-metrics:latest
      register: quay_pull
```

## Grafana Dashboard for Quay Metrics

Create a new dashboard JSON file `ansible/files/grafana_quay_dashboard.json`:

```json
{
  "dashboard": {
    "title": "Red Hat Quay Metrics",
    "panels": [
      {
        "title": "Repository Operations",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(quay_repository_pulls_total[5m])",
            "legendFormat": "Pulls/sec"
          },
          {
            "expr": "rate(quay_repository_pushes_total[5m])",
            "legendFormat": "Pushes/sec"
          }
        ]
      },
      {
        "title": "Storage Usage",
        "type": "gauge",
        "targets": [
          {
            "expr": "quay_storage_usage_bytes",
            "legendFormat": "Storage Used"
          }
        ]
      }
    ]
  }
}
```

## Security Considerations

### 1. Credential Management
Use Ansible Vault for Quay credentials:

```bash
# Create encrypted credentials file
ansible-vault create ansible/group_vars/quay_secrets.yml

# Add content:
quay_username: your_username
quay_password: your_secure_password
```

### 2. Image Security Scanning
Quay provides built-in security scanning. Configure alerts:

```yaml
# In Prometheus alerting rules
- alert: QuaySecurityVulnerabilities
  expr: quay_security_scans_vulnerabilities_total > 0
  for: 5m
  annotations:
    summary: "Security vulnerabilities detected in Quay images"
```

## Migration Strategy

### Phase 1: Setup and Testing
1. Create Quay.io account (free tier)
2. Add Quay metrics to Prometheus
3. Test pulling public images from Quay
4. Create Grafana dashboard for Quay metrics

### Phase 2: Gradual Migration
1. Push non-sensitive images to Quay public repos
2. Update playbooks to reference Quay images where appropriate
3. Set up automated image builds on Quay (if needed)

### Phase 3: Production Integration
1. Configure private repositories (if subscription allows)
2. Set up image mirroring between local registry and Quay
3. Implement Quay-based CI/CD workflows

## Benefits of Using Quay

1. **Enterprise Features**: Security scanning, geo-replication, fine-grained access control
2. **Monitoring**: Rich Prometheus metrics for your existing stack
3. **Reliability**: High availability and performance
4. **Integration**: Native Red Hat ecosystem integration
5. **Security**: Automated vulnerability scanning and reporting

## Cost Analysis

### Free Tier Limitations
- Public repositories: Unlimited
- Private repositories: Limited (check current Quay.io pricing)
- Build automation: Limited minutes/month
- Storage: Limited per account

### When to Consider Paid Subscription
- Need for many private repositories
- High-volume CI/CD pipelines
- Advanced security and compliance features
- Enterprise support requirements

## Implementation Steps

1. **Immediate (Free)**:
   ```bash
   # Add to your deployment
   cd /home/runner/work/VMStation/VMStation
   # Update prometheus config to include Quay metrics
   # Deploy updated monitoring stack
   ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml
   ```

2. **Next Steps**:
   - Sign up for Quay.io free account
   - Create public repository for VMStation images
   - Push your custom images to Quay public repos
   - Monitor Quay metrics in Grafana

## Conclusion

Red Hat Quay can be effectively used for free in your VMStation project, especially for:
- Public container images
- Learning enterprise registry features
- Adding rich metrics to your existing monitoring stack
- Improving image security with scanning

The hybrid approach allows you to keep your current local registry while gaining Quay's benefits for appropriate use cases.