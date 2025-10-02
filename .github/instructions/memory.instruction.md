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

## Conversation History
- Created an Ansible role `network-fix` and playbook `ansible/playbooks/network-fix.yaml` to apply kernel/module/sysctl changes and restart CNI components.

## Notes
- Fix targets common causes of "no route to host" from pod to host IPs (sysctl and br_netfilter missing or ip_forward/iptables blocking).
