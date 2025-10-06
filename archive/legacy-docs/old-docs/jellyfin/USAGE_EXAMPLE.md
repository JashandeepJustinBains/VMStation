# Jellyfin HA Deployment Example

## Scenario: Family Movie Night with Auto-Scaling

This example demonstrates how the Jellyfin HA deployment automatically scales based on usage:

### Initial State (1 User)
```bash
# Check initial deployment
kubectl get pods -n jellyfin
# NAME                        READY   STATUS    RESTARTS   AGE
# jellyfin-6b4c8d5f7b-xp9k2   1/1     Running   0          5m

kubectl get hpa -n jellyfin
# NAME           REFERENCE             TARGETS   MINPODS   MAXPODS   REPLICAS
# jellyfin-hpa   Deployment/jellyfin   20%/60%   1         3         1
```

**User Experience**: Dad starts watching a 4K movie. Single pod handles transcoding efficiently with hardware acceleration.

### Peak Usage (3+ Concurrent Users)
```bash
# As more family members start streaming...
kubectl get pods -n jellyfin
# NAME                        READY   STATUS    RESTARTS   AGE
# jellyfin-6b4c8d5f7b-xp9k2   1/1     Running   0          15m
# jellyfin-6b4c8d5f7b-m8w4t   1/1     Running   0          2m
# jellyfin-6b4c8d5f7b-n7q3r   1/1     Running   0          1m

kubectl get hpa -n jellyfin
# NAME           REFERENCE             TARGETS   MINPODS   MAXPODS   REPLICAS
# jellyfin-hpa   Deployment/jellyfin   75%/60%   1         3         3
```

**User Experience**: 
- Mom starts watching a show on her tablet
- Kids start streaming cartoons in their room
- Auto-scaling kicks in, new pods spin up
- Session affinity ensures each user stays connected to their pod
- No interruption or buffering during scaling

### Resource Monitoring
```bash
# Monitor resource usage during peak
kubectl top pods -n jellyfin
# NAME                        CPU(cores)   MEMORY(bytes)   
# jellyfin-6b4c8d5f7b-xp9k2   1200m        2100Mi          
# jellyfin-6b4c8d5f7b-m8w4t   800m         1800Mi          
# jellyfin-6b4c8d5f7b-n7q3r   600m         1600Mi          

# Total usage: ~2.6 CPU cores, ~5.5GB RAM (within 8GB storage node limit)
```

### Automatic Scale Down
```bash
# After movie night ends (5+ minutes of low usage)
kubectl get pods -n jellyfin
# NAME                        READY   STATUS        RESTARTS   AGE
# jellyfin-6b4c8d5f7b-xp9k2   1/1     Running       0          45m
# jellyfin-6b4c8d5f7b-m8w4t   1/1     Terminating   0          32m
# jellyfin-6b4c8d5f7b-n7q3r   1/1     Terminating   0          31m

kubectl get hpa -n jellyfin
# NAME           REFERENCE             TARGETS   MINPODS   MAXPODS   REPLICAS
# jellyfin-hpa   Deployment/jellyfin   15%/60%   1         3         1
```

**User Experience**: System automatically scales down, saving resources while maintaining service availability.

## Access Methods

### Family Access Points
- **Living Room Smart TV**: http://192.168.4.63:30096
- **Mobile Devices**: Same URL, responsive interface
- **Gaming Console**: DLNA discovery automatically finds server
- **Laptop/Desktop**: Direct access via any node IP

### Load Balancing in Action
```bash
# Each family member gets load-balanced automatically
curl -I http://192.168.4.63:30096
# Session-Cookie: jellyfin-server=pod1

curl -I http://192.168.4.63:30096  
# Session-Cookie: jellyfin-server=pod2

# Subsequent requests from same IP stick to assigned pod
```

## Hardware Acceleration Benefits

### Transcoding Performance
- **Without HW Accel**: 1080p → 720p uses ~2 CPU cores
- **With HW Accel**: Same transcode uses ~0.3 CPU cores + GPU
- **4K Support**: Can handle 4K→1080p transcoding efficiently
- **Multiple Streams**: GPU handles multiple concurrent transcodes

### Codec Support
- **H.264**: Standard HD content, universal compatibility
- **HEVC (H.265)**: 4K content, 50% smaller file sizes
- **VP9**: YouTube/WebM content, efficient streaming
- **AV1**: Future-proof codec, best compression

## Monitoring Dashboard

Access Grafana at http://192.168.4.63:30300 to see:
- Real-time pod count and scaling events
- Memory/CPU usage per pod
- Active transcoding sessions
- Network throughput for streaming
- Storage usage trends

## Troubleshooting Example

### Issue: Scaling Not Working
```bash
# Check metrics server
kubectl top nodes
# If this fails, metrics server needs installation

# Check HPA status
kubectl describe hpa jellyfin-hpa -n jellyfin
# Look for scaling events and conditions

# Check pod resource requests/limits
kubectl describe pod -n jellyfin -l app=jellyfin
# Verify resource constraints are set correctly
```

### Issue: Media Not Accessible
```bash
# Check persistent volume status
kubectl get pv | grep jellyfin
kubectl describe pvc -n jellyfin

# Verify storage node connectivity
kubectl exec -n jellyfin deployment/jellyfin -- ls -la /media
# Should show TV Shows, Movies directories

# Check permissions
kubectl exec -n jellyfin deployment/jellyfin -- id
# Should run as root (uid=0) for hardware access
```

## Migration Success Story

### Before (Podman)
- Single container on storage node
- Manual restart if container fails
- No load balancing for multiple users
- Resource contention during peak usage
- Manual scaling decisions

### After (Kubernetes HA)
- Automatic scaling based on real usage
- Self-healing pods with restart policies  
- Load balancing with session persistence
- Resource optimization within hardware limits
- Zero-downtime updates and maintenance

This deployment transforms a simple media server into an enterprise-grade streaming platform that automatically adapts to family usage patterns while maintaining seamless user experience.