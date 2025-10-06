# VMStation Repository - Quick Reference

## What You Have

A clean, minimal, production-ready Ansible deployment for mixed Debian/RHEL Kubernetes clusters.

## File Structure

```
VMStation/
├── README.md                    # Start here
├── deploy.md                    # Deployment guide
├── architecture.md              # Cluster design
├── troubleshooting.md           # Diagnostics
├── MIGRATION_NOTE.md            # What changed
├── deploy.sh                    # Main deployment script
├── ansible/
│   ├── inventory/
│   │   ├── hosts.yml            # Inventory (3 nodes)
│   │   └── group_vars/
│   │       ├── all.yml.template # Config template
│   │       └── secrets.yml.example # Vault secrets template
│   ├── playbooks/
│   │   ├── deploy-cluster.yaml  # Debian kubeadm deployment
│   │   ├── install-rke2-homelab.yml # RKE2 deployment
│   │   ├── reset-cluster.yaml   # Comprehensive reset
│   │   └── verify-cluster.yaml  # Validation
│   └── roles/
│       ├── install-k8s-binaries/
│       ├── preflight/
│       ├── network-fix/
│       ├── rke2/
│       ├── cluster-reset/
│       └── jellyfin/
├── tests/
│   ├── test-syntax.sh           # Syntax validation
│   ├── test-deploy-dryrun.sh    # Dry-run tests
│   ├── test-idempotence.sh      # Multi-cycle testing
│   └── test-smoke.sh            # Health checks
└── archive/
    └── legacy-docs/             # 88 archived docs
```

## Commands

### Deploy
```bash
./deploy.sh all --with-rke2 --yes   # Deploy everything
./deploy.sh debian                  # Debian cluster only
./deploy.sh rke2                    # RKE2 cluster only
```

### Reset
```bash
./deploy.sh reset                   # Reset all clusters
```

### Test
```bash
./tests/test-syntax.sh              # Validate syntax
./tests/test-smoke.sh               # Health checks
./tests/test-idempotence.sh         # Test 2+ cycles
```

## Infrastructure

### Debian Cluster (kubeadm)
- **masternode** (192.168.4.63) - Control plane
- **storagenodet3500** (192.168.4.61) - Worker, Jellyfin
- Kubernetes v1.29.15, Flannel CNI, containerd

### RKE2 Cluster (RHEL 10)
- **homelab** (192.168.4.62) - Single-node RKE2
- RKE2 v1.29.x, Canal CNI, monitoring federation

## Key Features

✅ **Idempotent** - Can run deploy → reset → deploy 100+ times
✅ **OS-Aware** - Handles Debian (iptables) and RHEL (nftables)
✅ **Clean Separation** - No OS mixing issues
✅ **Minimal Docs** - 4 focused documents (from 88)
✅ **Test Scripts** - Comprehensive validation
✅ **Auto-Sleep** - Cost optimization with Wake-on-LAN

## Next Steps

1. **Read**: `README.md` and `deploy.md`
2. **Configure**: Copy `ansible/inventory/group_vars/all.yml.template` to `all.yml`
3. **Secrets**: Create vault secrets if needed (RHEL sudo password)
4. **Deploy**: Run `./deploy.sh all --with-rke2 --yes`
5. **Verify**: Run `./tests/test-smoke.sh`
6. **Test**: Run `./tests/test-idempotence.sh 2` (2 cycles)

## Documentation

- **README.md** - Overview and quick start
- **deploy.md** - Detailed deployment guide
- **architecture.md** - Cluster design and rationale
- **troubleshooting.md** - 10 diagnostic checks
- **MIGRATION_NOTE.md** - What changed in this revamp

## Support

- Historical docs: `archive/legacy-docs/`
- Test failures: Check `troubleshooting.md`
- Deployment issues: See `deploy.md`

## Status

✅ Repository cleaned and minimized
✅ Test infrastructure in place
✅ Existing roles and playbooks validated
✅ Documentation focused and clear
✅ All syntax checks pass

Optional: Add full monitoring stack to Debian cluster (Prometheus/Grafana/Loki). Currently uses RKE2 federation.
