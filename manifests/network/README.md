# Network Manifests

CoreDNS, kube-proxy config, and related networking components.

- `coredns-*` files manage DNS in-cluster
- `kube-proxy-configmap.yaml` for proxy tuning

Use `kubectl -n kube-system rollout restart deploy/coredns` after ConfigMap changes.
