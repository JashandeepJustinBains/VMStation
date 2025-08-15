# Stack Overview

This document describes the main options for running workloads in your homelab:

## Kubernetes (k8s)
- Full-featured container orchestration
- Best for large clusters and advanced networking
- Requires more resources (RAM/CPU)

## Podman
- Lightweight container engine
- Can run pods and containers without a daemon
- Good for single-node setups or smaller clusters

## VMs
- Use for legacy workloads or isolation
- Can be managed with libvirt, Proxmox, or similar

## Recommendation
## Recommendation

For your use case (personal webapps, Jellyfin, moderate traffic, free tunnel service):
- **k3s**: Lightweight Kubernetes, ideal for small clusters and easy to manage. Good for webapps and Jellyfin, with future scalability.
- **Podman**: Simple for single-node setups, but less orchestration. Use if you want minimal overhead.
- **VMs**: Use for legacy apps or strong isolation, but more resource intensive.
- **Full k8s**: Only needed for large-scale, complex deployments.

**Recommended:**
