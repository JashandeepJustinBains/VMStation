# Kubernetes Manifests

Declarative Kubernetes resources for VMStation.

- Monitoring stack: `monitoring/`
- Infrastructure services: `infrastructure/`
- Networking components: `network/`
- Application examples: `jellyfin/`
- Staging/overrides: `staging-*/`

## Deployment

Manifests are generally applied by Ansible playbooks; for manual usage:

- `kubectl apply -f monitoring/`
- `kubectl apply -f infrastructure/`

Ensure kubeconfig is set and context points to the cluster.
