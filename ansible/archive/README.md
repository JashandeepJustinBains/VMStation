Legacy playbooks and archived materials
=====================================

This directory contains archived/legacy playbooks and heavy migration/repair playbooks that were
moved out of the active `ansible/playbooks/` area to simplify the maintenance surface.

If you need to inspect or re-use an archived playbook, see the files inside this directory.

Guidance:
- Active, minimal deploy flow: `ansible/playbooks/deploy-cluster.yaml`
- Archive contains: cluster-bootstrap, minimal-network-fix, verify-cluster, and setup-cluster (heavy)
- Do not run archived playbooks unless you understand their purpose — prefer the minimal flow.
