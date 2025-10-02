---
applyTo: '**'
---

# User Memory

## User Preferences
- Programming languages: not specified (Ansible/YAML used here)
- Code style preferences: follow repository conventions
- Development environment: homelab, Linux servers orchestrated via Ansible
- Communication style: concise, actionable

## Project Context
- Current project type: homelab Kubernetes cluster automation
- Tech stack: kubeadm, flannel CNI, Ansible for automation
- Architecture patterns: control-plane and worker nodes managed by Ansible playbooks
- All playbooks and scripts must reside in the actual repo root (F:\VMStation), never in F:\f\ or other paths.

## Conversation History
- Created an Ansible role `network-fix` and playbook `ansible/playbooks/network-fix.yaml` to apply kernel/module/sysctl changes and restart CNI components.
- Replaced multi-document spin-down-cluster.yaml with a single-play, valid Ansible playbook that wraps the cluster-spindown role and accepts spin_targets from extra-vars.
- Next: Fix deploy.sh logging so it does not contaminate Ansible extra-vars (send info to stderr).

## Notes
- Fix targets common causes of "no route to host" from pod to host IPs (sysctl and br_netfilter missing or ip_forward/iptables blocking).
