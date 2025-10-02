Network Fix Playbook
====================

This playbook applies node-level networking hardening and fixes that are commonly required for Kubernetes CNI plugins to function correctly.

Run:
- ansible-playbook -i ansible/inventory.txt ansible/playbooks/network-fix.yaml

What it does:
- Loads and persists br_netfilter
- Ensures net.bridge.bridge-nf-call-iptables and ip_forward are enabled
- Attempts to set iptables FORWARD ACCEPT
- Stops/disables ufw if present
- Restarts kubelet to pick up changes
- Restarts flannel and kube-proxy rollout on the masternode
