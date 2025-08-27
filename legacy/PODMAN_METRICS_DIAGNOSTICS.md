# Podman System Metrics Diagnostic Commands

## Summary Decision
**Create comprehensive diagnostic toolkit with exact commands and Ansible automation for podman_system_metrics container issues**

## Requirements Mapping
- **Artifact Collection**: Done - Exact commands provided for all 7 required artifacts
- **Image Analysis**: Done - Commands to inspect image config and determine if long-running
- **Ansible Playbook**: Done - Idempotent debug_podman_metrics.yaml created
- **Verification Steps**: Done - Exact commands and expected outputs provided
- **Rollback Plan**: Done - Simple steps to revert changes

## Files Changed
- `ansible/group_vars/all.yml.template` - Configuration template with podman_system_metrics_host_port=19882
- `ansible/plays/monitoring/debug_podman_metrics.yaml` - Complete diagnostic and remediation playbook

## Validation Results

### Exact Commands to Run (Copy-Paste Ready)

Run these commands **in order** on the monitoring host (192.168.4.63):

```bash
# Replace {{ podman_system_metrics_host_port }} with 19882 in all commands below

# 1. Container status with ports and image info
podman ps -a --filter name=podman_system_metrics --format 'table {{.ID}} {{.Names}} {{.Status}} {{.Image}} {{.Ports}}'

# 2. Container inspect state
podman inspect podman_system_metrics --format '{{json .State}}'

# 3. Container logs (last 500 lines with timestamps)  
podman logs --timestamps --tail 500 podman_system_metrics || true

# 4. Check port usage on host
ss -ltnp | grep -E '127\.0\.0\.1:19882|:19882\b' || true

# 5. Test metrics endpoint
curl -v --connect-timeout 5 http://127.0.0.1:19882/metrics

# 6. Image configuration inspect
podman inspect 192.168.4.63:5000/podman-system-metrics:latest --format '{{json .Config}}'

# 7. Foreground reproduction test
podman rm -f podman_system_metrics 2>/dev/null || true
podman run --rm --name podman_system_metrics --publish 127.0.0.1:19882:9882 192.168.4.63:5000/podman-system-metrics:latest
```

### How to Interpret Results

#### Command 1 (Container Status)
- **Expected**: `Up X minutes` in Status column
- **Problem**: `Exited (0)` or `Exited (1)` indicates immediate exit
- **Action**: Check logs (command 3) and image config (command 6)

#### Command 2 (Container Inspect)  
- **Expected**: `"Status": "running", "Running": true`
- **Problem**: `"Status": "exited", "ExitCode": 0` indicates clean exit
- **Action**: Container likely ran once and completed - not a long-running service

#### Command 3 (Container Logs)
- **Expected**: Startup messages and ongoing metrics collection logs
- **Problem**: Empty logs or immediate exit messages
- **Action**: Image may be misconfigured or missing dependencies

#### Command 4 (Port Check)
- **Expected**: `127.0.0.1:19882` with `LISTEN` state
- **Problem**: No output means port not in use
- **Action**: Container not binding to port successfully

#### Command 5 (Metrics Test)
- **Expected**: HTTP 200 with Prometheus format metrics
- **Problem**: Connection refused or timeout
- **Action**: Container not exposing metrics endpoint

#### Command 6 (Image Config)
- **Expected**: `"ExposedPorts": {"9882/tcp": {}}, "Entrypoint": [...], "Cmd": [...]`
- **Problem**: Missing ExposedPorts or wrong entrypoint
- **Action**: Image may be wrong type or need different configuration

#### Command 7 (Foreground Test)
- **Expected**: Container runs continuously with metric logs
- **Problem**: Immediate exit with error or "not found" 
- **Action**: Image compatibility issue or missing host resources

### Common Problem Patterns

#### Pattern 1: Container Exits Immediately (ExitCode 0)
**Interpretation**: Image is a one-shot command, not a service
**Solution**: 
```bash
# Check what the image actually does
podman inspect 192.168.4.63:5000/podman-system-metrics:latest --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'

# Use a proper metrics exporter image instead
podman pull quay.io/podman/stable
podman tag quay.io/podman/stable 192.168.4.63:5000/podman-system-metrics:latest
```

#### Pattern 2: Permission/Socket Errors  
**Interpretation**: Container needs access to Podman socket
**Solution**:
```bash
# Add required volume mount and capabilities
podman run -d --name podman_system_metrics \
  --publish 127.0.0.1:19882:9882 \
  --volume /run/podman/podman.sock:/run/podman/podman.sock:ro \
  --cap-add SYS_ADMIN \
  192.168.4.63:5000/podman-system-metrics:latest
```

#### Pattern 3: Port Already in Use
**Interpretation**: Host `podman system service` or other process using port
**Solution**:
```bash
# Stop conflicting service
sudo systemctl stop podman.socket
sudo pkill -f "podman.*system.*service"

# Or use different port in ansible/group_vars/all.yml
echo "podman_system_metrics_host_port: 19883" >> ansible/group_vars/all.yml
```

## Minimal Remediation Steps

### 1. Create Configuration (if missing)
```bash
mkdir -p ansible/group_vars
cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml
```

### 2. Run Ansible Diagnostic Playbook
```bash
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/debug_podman_metrics.yaml
```

### 3. Check Results  
```bash
ls -la /srv/monitoring_data/VMStation/debug/
cat /srv/monitoring_data/VMStation/debug/podman_metrics_debug_*.txt
```

### 4. Manual Fix (if Ansible fails)
```bash
# Stop conflicts
sudo systemctl stop podman.socket

# Remove old container
podman rm -f podman_system_metrics

# Start with proper config
podman run -d --name podman_system_metrics \
  --restart always \
  --publish 127.0.0.1:19882:9882 \
  --volume /run/podman/podman.sock:/run/podman/podman.sock:ro \
  192.168.4.63:5000/podman-system-metrics:latest

# Verify
curl http://127.0.0.1:19882/metrics
```

## Verification Commands

After applying fixes:
```bash
# 1. Container should be running
podman ps --filter name=podman_system_metrics

# 2. Port should be listening  
ss -ltnp | grep :19882

# 3. Metrics should return data
curl -s http://127.0.0.1:19882/metrics | head -10

# 4. Prometheus should see target (if configured)
curl -s http://192.168.4.63:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="podman_system_metrics")'
```

**Expected Results:**
- Container status: `Up`
- Port: `127.0.0.1:19882` in LISTEN state  
- Metrics: Prometheus format output with `podman_` prefixed metrics
- Prometheus: Target state `up`

## Rollback Plan

If changes cause issues:
```bash
# 1. Stop container
podman stop podman_system_metrics
podman rm podman_system_metrics

# 2. Restart original service (if was running)
sudo systemctl start podman.socket

# 3. Remove config changes
rm -f ansible/group_vars/all.yml

# 4. Revert to original state
ansible-playbook -i ansible/inventory.txt ansible/plays/monitoring/cleanup.yaml
```

## Success Criteria
- Container shows `Up` status continuously
- Port 19882 accessible on localhost  
- `/metrics` endpoint returns Prometheus format data
- No errors in container logs
- Prometheus can scrape target successfully