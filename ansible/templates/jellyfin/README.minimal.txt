# Jellyfin Minimal Kubernetes Deployment

## Overview
This is a minimal Jellyfin deployment that runs ONLY on the storage node (storagenodet3500).

## Pre-requisites
- Media is pre-mounted and populated at /srv/media on storagenodet3500
- Do NOT create or modify /srv/media

## Deployment
1. Apply manifests in order:
   ```bash
   kubectl apply -f namespace.yaml
   kubectl apply -f persistent-volume.yaml
   kubectl apply -f persistent-volume-claim.yaml
   kubectl apply -f deployment.yaml
   kubectl apply -f service.yaml
   ```

## Storage Configuration
- **Media**: /srv/media on storagenodet3500 (read-only mount to container)
- **App Data**: /jellyfin on storagenodet3500 (via PersistentVolume)

## Access
- Service exposes port 8096 via NodePort 30096
- Access via: http://[any-cluster-node-ip]:30096

## Initial Setup
After first run, admin must configure Jellyfin libraries to point to /srv/media inside the container.

## Node Placement
- Deployment enforced to run on storagenodet3500 via nodeSelector
- PersistentVolume enforced to storagenodet3500 via nodeAffinity
- Ensures storage and compute are on the same node