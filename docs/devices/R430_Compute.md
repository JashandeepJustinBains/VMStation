# Dell R430 Compute Engine

## Role
- Main compute node for cluster workloads
- Runs Kubernetes/Podman/VMs

## Setup Notes
- OS: Debian Linux (Headless)
- RAM: Upgraded for more workloads
- Network: Static IP

## Services
- Kubernetes (k8s) or Podman
- CI/CD runners
- Monitoring agent

## Tips
- Consider full k8s or Podman for container orchestration
- Use VMs for legacy workloads
