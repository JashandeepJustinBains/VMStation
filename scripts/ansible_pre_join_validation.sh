#!/bin/bash

# VMStation Pre-Join Validation Script for Ansible
# Handles crictl permissions and containerd validation properly

set -e

CONTROL_PLANE_IP="${1:-192.168.4.63}"
WORKER_WAS_WIPED="${2:-false}"

echo "=== Pre-Join Validation for Post-Wipe Worker ==="
echo "Timestamp: $(date)"
echo "Control-plane IP: $CONTROL_PLANE_IP"
echo "Worker was wiped: $WORKER_WAS_WIPED"
echo ""

# Validate containerd is properly initialized for wiped workers
if ! systemctl is-active containerd >/dev/null 2>&1; then
  echo "ERROR: containerd is not running"
  systemctl status containerd --no-pager || true
  exit 1
fi
echo "✓ containerd service is active"

# Configure crictl to communicate with containerd before validation
echo "Configuring crictl for containerd communication..."
mkdir -p /etc
cat > /etc/crictl.yaml << 'CRICTL_EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
CRICTL_EOF
echo "✓ crictl configuration created"

# Fix containerd socket permissions for crictl access
echo "Checking and fixing containerd socket permissions..."
if [ -S /run/containerd/containerd.sock ]; then
  # Ensure socket permissions allow access
  socket_perms=$(stat -c "%a" /run/containerd/containerd.sock 2>/dev/null || echo "unknown")
  socket_owner=$(stat -c "%U:%G" /run/containerd/containerd.sock 2>/dev/null || echo "unknown")
  echo "Containerd socket permissions: ${socket_perms} (${socket_owner})"
  
  # Create containerd group if it doesn't exist for better permissions management  
  if ! getent group containerd >/dev/null 2>&1; then
    echo "Creating containerd group for socket access..."
    groupadd containerd 2>/dev/null || true
    # Change socket group to containerd for better access control
    chgrp containerd /run/containerd/containerd.sock 2>/dev/null || true
    echo "✓ containerd group created and socket permissions updated"
  fi
fi

# Test crictl communication with containerd with timeout protection
echo "Testing crictl communication with containerd..."
crictl_timeout=30  # Reduced timeout for faster detection

# Check if containerd socket exists first
if [ ! -S /run/containerd/containerd.sock ]; then
  echo "WARNING: containerd socket not found, ensuring containerd is properly started..."
  systemctl stop containerd 2>/dev/null || true
  sleep 2
  systemctl start containerd
  # Wait for socket to be created
  socket_wait=0
  while [ $socket_wait -lt 30 ] && [ ! -S /run/containerd/containerd.sock ]; do
    sleep 1
    socket_wait=$((socket_wait + 1))
  done
  
  if [ ! -S /run/containerd/containerd.sock ]; then
    echo "ERROR: containerd socket still not available after restart"
    systemctl status containerd --no-pager || true
    exit 1
  fi
  echo "✓ containerd socket created"
fi

# Use timeout command to prevent crictl from hanging indefinitely  
# Run crictl with proper error handling for permission issues
if timeout $crictl_timeout crictl info >/dev/null 2>&1; then
  echo "✓ crictl communication working"
else
  echo "WARNING: crictl cannot communicate with containerd within ${crictl_timeout}s"
  echo "Attempting enhanced containerd restart and initialization..."
  
  # Stop containerd completely first
  systemctl stop containerd 2>/dev/null || true
  sleep 3
  
  # Clean any stale containerd state that might block communication
  rm -rf /run/containerd/* 2>/dev/null || true
  
  # Ensure containerd config exists and is valid
  if [ ! -f /etc/containerd/config.toml ]; then
    echo "Creating containerd configuration..."
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    # Enable systemd cgroup driver for Kubernetes compatibility
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  fi
  
  # Start containerd and wait for proper initialization
  systemctl start containerd
  sleep 15  # Allow time for full initialization
  
  # Initialize containerd image filesystem to prevent communication issues
  echo "Initializing containerd image filesystem..."
  ctr namespace create k8s.io 2>/dev/null || true
  ctr --namespace k8s.io images ls >/dev/null 2>&1 || true
  sleep 5
  
  # Retry crictl communication with exponential backoff and proper permissions
  retry_count=0
  max_retries=6  # Increased to 6 retries for better reliability
  while [ $retry_count -lt $max_retries ]; do
    # Ensure containerd socket has proper permissions before each retry
    if [ -S /run/containerd/containerd.sock ]; then
      chgrp containerd /run/containerd/containerd.sock 2>/dev/null || true
    fi
    
    if timeout $crictl_timeout crictl info >/dev/null 2>&1; then
      echo "✓ crictl communication restored after enhanced restart (attempt $((retry_count + 1)))"
      break
    else
      echo "  Waiting for containerd initialization... ($((retry_count + 1))/$max_retries)"
      # Exponential backoff: 5s, 10s, 15s, 20s, 25s, 30s
      sleep_time=$((5 + retry_count * 5))
      sleep $sleep_time
      retry_count=$((retry_count + 1))
    fi
  done
  
  if [ $retry_count -eq $max_retries ]; then
    echo "ERROR: crictl still cannot communicate with containerd after enhanced restart"
    echo "This indicates a persistent containerd configuration issue"
    echo "Containerd status:"
    systemctl status containerd --no-pager || true
    echo ""
    echo "Socket status:"
    ls -la /run/containerd/ 2>/dev/null || echo "No containerd runtime directory"
    echo ""
    echo "Containerd logs (last 20 lines):"
    journalctl -u containerd --no-pager -n 20 || true
    exit 1
  fi
fi

# Initialize containerd image filesystem for kubelet
echo "Initializing containerd image filesystem..."
ctr namespace create k8s.io 2>/dev/null || true

# Use timeout for ctr operations to prevent hanging
if timeout 15 ctr --namespace k8s.io images ls >/dev/null 2>&1; then
  echo "✓ containerd image filesystem initialized"
else
  echo "WARNING: containerd image filesystem initialization timed out"
  echo "This may cause kubelet join issues"
fi

# Check network connectivity to control-plane with timeout
echo "Testing connectivity to control-plane..."
if timeout 10 bash -c "</dev/tcp/$CONTROL_PLANE_IP/6443" 2>/dev/null; then
  echo "✓ Control-plane connectivity verified"
else
  echo "ERROR: Cannot connect to control-plane API server at $CONTROL_PLANE_IP:6443"
  echo "Network connectivity test failed"
  exit 1
fi

echo "✅ Pre-join validation completed successfully"