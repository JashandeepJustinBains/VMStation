# Podman System Metrics Troubleshooting Guide

This guide provides exact commands to diagnose and fix issues with `podman_system_metrics` exiting immediately and port 19882 refusing connections.

## Root Cause Analysis

The `podman_system_metrics` container fails for these common reasons:
1. **Missing container image** - The local registry doesn't have the required image
2. **Undefined configuration** - `podman_system_metrics_host_port` variable not set
3. **Port conflicts** - Another process is using port 19882
4. **Registry access issues** - Insecure registry not configured
5. **Podman socket permissions** - Container can't access Podman API

## Quick Fix

Run the automated fix script:
```bash
# Run the complete fix
./scripts/fix_podman_metrics.sh
```

## Quick Diagnosis

Run the comprehensive diagnostic script:
```bash
# Run diagnostic analysis
./scripts/podman_metrics_diagnostic.sh
```

## Manual Step-by-Step Troubleshooting

### 1. Check Container Status
```bash
# Check if container exists and its status
podman ps -a --filter name="podman_system_metrics"

# Check container logs
podman logs podman_system_metrics

# If container doesn't exist, check if it was created
podman ps -a | grep podman
```

**Interpretation:**
- Status "Exited (X)" = Container started but exited with code X
- Empty result = Container was never created
- Status "Running" = Container is running (issue might be elsewhere)

### 2. Check Port Usage
```bash
# Check what's using port 19882
sudo lsof -i :19882
# Alternative if lsof not available:
ss -tlnp | grep ':19882'
# Or:
sudo netstat -tlnp | grep ':19882'
```

**Interpretation:**
- Output shows process = Port is in use by another service
- No output = Port is free
- "podman" in output = Podman container is using the port

### 3. Check Image Availability
```bash
# Check if the image exists locally
podman images | grep podman-system-metrics

# Check local registry
curl http://192.168.4.63:5000/v2/_catalog

# Try to pull the image
podman pull 192.168.4.63:5000/podman-system-metrics:latest
```

**Interpretation:**
- No local image = Need to pull or build image
- Registry connection refused = Local registry is down
- Pull failed = Image doesn't exist in registry

### 4. Test Container Manually
```bash
# Remove any existing container
podman rm -f podman_system_metrics

# Try to run manually with debug output
podman run --name podman_system_metrics_test \
           --rm \
           -p 127.0.0.1:19882:9882 \
           192.168.4.63:5000/podman-system-metrics:latest
```

**Interpretation:**
- Immediate exit = Image/container issue
- "Permission denied" = Podman socket permissions
- "Port already in use" = Another service using port
- Running successfully = Ansible configuration issue

### 5. Check Podman System Health
```bash
# Check Podman service status
systemctl status podman.socket
sudo systemctl status podman.socket

# Check Podman socket
ls -la /run/podman/podman.sock
ls -la /run/user/$(id -u)/podman/podman.sock

# Test Podman API
podman system info
```

**Interpretation:**
- Socket not found = Podman service not running
- Permission denied = Need to add user to podman group or run as root
- API works = Podman is healthy

## Common Fixes

### Fix 1: Missing Configuration
If `podman_system_metrics_host_port` is undefined:
```bash
# Create the configuration file from template
mkdir -p ansible/group_vars
cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml

# Or create manually:
cat > ansible/group_vars/all.yml << EOF
---
enable_podman_exporters: true
podman_system_metrics_host_port: 19882
EOF
```

### Fix 2: Port Conflict
If another service is using port 19882:
```bash
# Option A: Kill the conflicting process
sudo kill $(sudo lsof -t -i:19882)

# Option B: Use a different port
sed -i 's/podman_system_metrics_host_port: 19882/podman_system_metrics_host_port: 19883/' ansible/group_vars/all.yml
```

### Fix 3: Missing Image
If the container image doesn't exist:
```bash
# Check if local registry is running
curl http://192.168.4.63:5000/v2/_catalog

# If registry is down, start it:
podman run -d --name registry \
           -p 5000:5000 \
           -v /srv/monitoring_data/registry:/var/lib/registry \
           docker.io/registry:2

# Build and push the image (if you have the Dockerfile):
# podman build -t podman-system-metrics .
# podman tag podman-system-metrics 192.168.4.63:5000/podman-system-metrics:latest
# podman push 192.168.4.63:5000/podman-system-metrics:latest
```

### Fix 4: Podman Service Issues
If Podman socket is not available:
```bash
# Start Podman socket service
systemctl --user start podman.socket
systemctl --user enable podman.socket

# Or system-wide:
sudo systemctl start podman.socket
sudo systemctl enable podman.socket

# Add user to podman group (if needed)
sudo usermod -aG podman $USER
newgrp podman
```

### Fix 5: Container Permissions
If container has permission issues:
```bash
# Run with proper SELinux context
podman run --name podman_system_metrics \
           -d \
           --restart always \
           -p 127.0.0.1:19882:9882 \
           -v /run/podman/podman.sock:/run/podman/podman.sock:Z \
           192.168.4.63:5000/podman-system-metrics:latest
```

## Testing the Fix

After applying fixes, test the metrics endpoint:
```bash
# Test local connection
curl http://127.0.0.1:19882/metrics

# Test from monitoring node (if different)
curl http://192.168.4.63:19882/metrics

# Check Prometheus can scrape
curl http://192.168.4.63:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="podman_system_metrics")'
```

**Expected Results:**
- Metrics endpoint returns Prometheus format metrics
- Prometheus shows target as "UP" in targets page
- No errors in container logs

## Ansible Re-deployment

Once issues are fixed, redeploy using Ansible:
```bash
# Deploy exporters only
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/install_exporters.yaml

# Or full monitoring stack
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring_stack.yaml

# Verify deployment
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/debug_collect.yaml
```