Network-fix Ansible Role
========================

Purpose:
- Ensure kernel modules and sysctl settings required by many Kubernetes CNIs (like flannel) are present.
- Apply basic iptables/ufw adjustments that commonly block pod-to-pod or host-to-pod traffic.
- Restart kubelet to pick up changes.

How to run:
- From the repository root run: ansible-playbook -i ansible/inventory.txt ansible/playbooks/network-fix.yaml

Notes:
- This role is best-effort and idempotent: actions that are already in the desired state will be left alone.
- The playbook tries to restart flannel and kube-proxy on the control plane using the local KUBECONFIG path; adjust if your admin.conf is somewhere else.
