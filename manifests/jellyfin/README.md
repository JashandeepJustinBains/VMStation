# Jellyfin Manifests

Media server deployment examples for the cluster.

- `jellyfin.yaml`: Full deployment with PVCs and NodePort
- `jellyfin-minimal.yaml`: Minimal example for testing

Apply with:

```bash
kubectl apply -f jellyfin/
```

Ensure storage class and node selectors match your environment.
