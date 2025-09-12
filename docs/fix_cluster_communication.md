## fix_cluster_communication.sh — Cluster communication fix orchestration

Path: `scripts/fix_cluster_communication.sh`

Summary
-------
This document describes what `fix_cluster_communication.sh` does, its prerequisites, safe usage, the individual fix steps it orchestrates, how to verify the cluster after running it, and common troubleshooting steps.

Purpose
-------
The script is an orchestration wrapper intended to remediate common cluster networking and node-agent problems that prevent pod networking and NodePort services from working. Typical issues it targets:

- iptables / nftables compatibility problems that prevent kube-proxy from programming NAT rules
- Flannel CNI misconfiguration or CNI bridge conflicts
- kube-proxy CrashLoopBackOffs or misbehaving proxy that breaks NodePort routing
- kubeconfig / kubectl configuration problems on worker nodes
- General pod-level networking problems that cause probes to fail ("no route to host")

It is not a magic repair tool; it runs a sequence of targeted helper scripts found in `scripts/` and performs basic validation.

Prerequisites and safety
------------------------
- Run as root (the script checks for root and will exit if not running as root).
- `kubectl` must be installed and configured on the machine where you run the script (preferably the control plane or a machine with cluster-admin kubeconfig).
- The script calls other scripts in the `scripts/` directory. Confirm those helper scripts are present and review them before running.
- The script is interactive: it pauses after initial diagnostics and waits for Enter to continue. This gives you a chance to review the diagnostics before making changes.
- Changing iptables/nft backend or restarting DaemonSets (flannel, kube-proxy) can cause temporary disruption of pod networking. Run during a maintenance window or on non-production clusters where possible.

What the script runs (high level)
---------------------------------
The orchestration script runs these named helper scripts (in order):

1. `fix_iptables_compatibility.sh` — attempts to resolve iptables / nftables compatibility issues that prevent correct NAT rules.
2. `fix_cni_bridge_conflict.sh` — resolves common CNI bridge conflicts (cni0 vs flannel devices, stale bridge interfaces, etc.).
3. `fix_remaining_pod_issues.sh` — targets kube-proxy and pods that are CrashLoopBackOff or failing readiness/startup probes.
4. `fix_worker_kubectl_config.sh` — repairs kubeconfig/kubectl issues on worker nodes (if present).
5. `validate_cluster_communication.sh` — runs a final validation pass (checks nodes, key pods, and NodePort reachability).

Usage
-----
On a machine with cluster-admin access and `kubectl` installed, run:

```bash
# from the repository root
sudo bash scripts/fix_cluster_communication.sh
```

The script will:

- run initial diagnostics and print cluster/node status
- prompt you to press Enter to proceed
- run the helper scripts in the order listed above
- wait briefly for services to restart and then run validation
- print a summary at the end

If you want to run the underlying helper scripts manually, run them directly in `scripts/` in the order above to control each step.

Verification
------------
After the script completes, verify:

1. Node and pod health:

```bash
kubectl get nodes -o wide
kubectl get pods --all-namespaces
kubectl get daemonset -n kube-system kube-proxy -o wide
kubectl get daemonset -n kube-flannel kube-flannel-ds -o wide || kubectl -n kube-system get pods -l app=kube-flannel
```

2. Check kube-proxy logs on nodes that previously had issues:

```bash
kubectl -n kube-system logs -l k8s-app=kube-proxy --tail=200
```

3. Check ip routing and NodePort rules on an affected node (replace <POD_IP> and <NODE_IP>):

```bash
ip -4 route show
ip route get <POD_IP>
sudo iptables -t nat -L KUBE-SERVICES -n --line-numbers || sudo nft list table ip nat
curl -sv --max-time 5 http://<NODE_IP>:<NODEPORT>/ || true
```

Troubleshooting & notes
-----------------------
- nftables vs legacy iptables: many modern distributions use the nftables kernel subsystem with an iptables compatibility layer. If you see messages like "chain `KUBE-SEP' in table `nat' is incompatible, use 'nft' tool", then kube-proxy or other components may be unable to create rules as expected. Options:
  - Use the distro's update-alternatives to switch iptables to the legacy backend (distro-specific; review before switching).
  - Ensure kube-proxy is running in a mode compatible with your host (iptables vs ipvs) and that the required kernel modules are present.

- Flannel/route oddities: if `ip route get <POD_IP>` behaves unexpectedly or flannel.1 shows a 0/32 address or a route that uses the network address as a gateway, try:
  - Restarting the flannel DaemonSet: `kubectl -n kube-system rollout restart daemonset kube-flannel-ds` (or the appropriate namespace/name in your cluster).
  - If route corruption persists, removing the stale `flannel.1` interface and restarting flannel on the node (careful, this affects running pods) or rebooting the node may clear the issue.

- Temporary workarounds: while you fix node networking you can still access services using:
  - `kubectl port-forward pod/<pod-name> 8096:8096` to reach a pod directly
  - Temporarily change readiness/startup probes to an exec that checks `127.0.0.1` so kubelet marks the pod Ready (this hides the network problem and should only be used as a short-lived workaround).

Risks and rollback
------------------
- The script may restart DaemonSets (flannel, kube-proxy) and make changes to iptables or system-level configuration. This can cause temporary loss of connectivity for services. Schedule during maintenance windows when possible.
- Rollback strategy: most changes are performed by helper scripts. If a helper script makes a persistent change to iptables backends, follow the helper's rollback instructions (the helper scripts should print their actions). If network disruption occurs, you can:
  - Restart affected DaemonSets again
  - Reboot the affected node(s)
  - Restore earlier iptables alternatives if you changed the iptables backend

Where to go next
----------------
- Review the helper scripts in `scripts/` (`fix_iptables_compatibility.sh`, `fix_cni_bridge_conflict.sh`, `fix_remaining_pod_issues.sh`, `fix_worker_kubectl_config.sh`, `validate_cluster_communication.sh`) before running the orchestration.
- If you'd like, I can generate a non-interactive / dry-run mode for the orchestration script, or prepare a patch that temporarily changes the Jellyfin readiness probe to use an exec check so the service becomes Ready while you repair CNI/kube-proxy.

Change log
----------
- 2025-09-12: Created documentation for `scripts/fix_cluster_communication.sh`.

License
-------
This documentation follows the repository license. See `LICENSE` for terms.
