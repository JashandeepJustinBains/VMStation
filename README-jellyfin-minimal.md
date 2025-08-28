# Jellyfin Minimal Kubernetes Deployment

## Quick Start

```bash
kubectl apply -f jellyfin-minimal.yml
kubectl get pods -n jellyfin -o wide
kubectl logs -n jellyfin -l app=jellyfin --tail=200
```

## Switching from hostPath to PVC

To use PersistentVolumeClaims instead of direct hostPath volumes:

1. Uncomment the PVC templates at the bottom of `jellyfin-minimal.yml`
2. Replace the hostPath volumes in the Pod spec with PVC references:
   ```yaml
   volumes:
   - name: media
     persistentVolumeClaim:
       claimName: jellyfin-media-pvc
   - name: config
     persistentVolumeClaim:
       claimName: jellyfin-config-pvc
   ```

## Enabling Metrics Exporter Sidecar

Jellyfin doesn't expose Prometheus metrics by default. The included ServiceMonitor scrapes Jellyfin's `/System/Info/Public` API endpoint for basic information. For proper metrics collection, deploy a lightweight metrics exporter sidecar (or enable a Jellyfin metrics plugin) so `/metrics` is available, then ServiceMonitor will pick it up automatically. See the commented examples in the YAML file for sidecar implementation details.

## Validation Commands

```bash
# Check deployment status
kubectl get pods -n jellyfin -o wide
kubectl describe pod jellyfin -n jellyfin
kubectl logs -n jellyfin -l app=jellyfin --tail=200
kubectl get svc -n jellyfin

# Verify ServiceMonitor (requires Prometheus Operator)
kubectl get servicemonitor -n jellyfin

# Test access
curl -I http://192.168.4.61:30096/health
```