# Design Decisions and Rationale

This document captures opinionated and nonstandard choices made in the VMStation project to improve operability in a homelab environment.

## UID ownership for monitoring PVs
- Prometheus: 65534
- Loki: 10001
- Grafana: 472

Reason: Avoids permission issues and reduces need for root-owned volumes while matching common upstream container UIDs.

## Headless services and FQDN usage
- Use FQDNs for headless services to ensure deterministic DNS resolution across namespaces and client search paths.

## Kubespray vs RKE2 separation
- RKE2 used only for a separate homelab RHEL10 node to avoid mixing runtime models and simplify lifecycle management.

## Containerd/socket resilience
- Preflight includes retries and alternate install paths for containerd; diagnostics saved to `ansible/artifacts/`.

## Windows development environment
- Development happens on Windows; operational scripts are validated in WSL; documentation recommends WSL for running playbooks.

## Secrets management
- All credentials must be stored in `ansible/group_vars/all/secrets.yml` encrypted with Ansible Vault. Sample variable names are documented in group_vars README.

---

For more details see `ansible/README.md` and `ansible/group_vars/README.md`.
