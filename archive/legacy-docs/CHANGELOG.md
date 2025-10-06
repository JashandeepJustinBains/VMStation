# VMStation Changelog

## [Unreleased]

### Added
- Network control plane reset functionality (`net-reset` command)
- Canonical kube-proxy and CoreDNS manifests with conservative defaults
- Comprehensive backup and diagnostics collection for network components
- Automatic verification and rollback capabilities for network reset operations
- Timestamped artifact storage in `ansible/artifacts/arc-network-diagnosis/`
- Network reset runbook with detailed safety procedures

### Enhanced
- `deploy-cluster.sh` with new `net-reset` command for surgical network fixes
- Safety confirmations for destructive operations (`--confirm` flag)
- Dry-run mode support for network reset operations
- Node discovery and cluster state documentation

### Fixed
- CoreDNS CrashLoopBackOff issues through fresh canonical deployment
- kube-proxy instability through iptables mode configuration
- Pod DNS and inter-pod connectivity failures via network control plane reset

## Previous Releases
(Previous entries would go here...)