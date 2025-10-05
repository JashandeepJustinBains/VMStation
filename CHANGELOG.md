# VMStation Changelog

## [Unreleased]

### Fixed (October 2025)
- **Critical**: kubectl uncordon command failure - invalid `--all` flag fixed by looping through nodes
- **Critical**: CrashLoopBackOff on kube-proxy and Flannel pods due to NFTables misconfiguration
- **Critical**: Deployment stopping at Phase 6 validation before deploy-apps and Jellyfin
- **Major**: Flannel EnableNFTables hardcoded to true, breaking Debian nodes with iptables backend
- **Major**: RHEL 10 network setup creating conflicting nftables rules when using iptables-nft
- **Moderate**: Reset playbook requiring manual confirmation, blocking automated testing
- **Moderate**: Validation running before pods stabilized from initial restart cycles

### Added (October 2025)
- kubeadm configuration template for explicit kube-proxy and cluster configuration
- Pod stabilization wait (150s) before validation to handle restart cycles
- Non-interactive reset mode with `reset_confirm=true` flag
- nftables service enablement for RHEL 10
- Comprehensive deployment fixes documentation (FIXES_OCT2025.md)
- Quick deployment guide for users (QUICK_DEPLOYMENT_GUIDE.md)

### Changed (October 2025)
- Flannel CNI now auto-detects iptables backend per node instead of global setting
- RHEL 10 network configuration simplified - removed manual nftables rule creation
- deploy-cluster.yaml now uses kubeadm config template instead of inline flags
- Reset playbook supports automated execution via deploy.sh

### Improved (October 2025)
- **Idempotency**: Can now run deploy -> reset -> deploy repeatedly without failures
- **Robustness**: All backbone pods work correctly on first deployment
- **OS Compatibility**: Proper handling of Debian (iptables) and RHEL 10 (nftables) in same cluster
- **Automation**: No manual intervention needed for deployment or reset

### Added (Previous)
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