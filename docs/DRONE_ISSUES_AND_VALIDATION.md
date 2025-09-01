DRONE: Troubleshooting, fixes, and validation

Summary
-------
This document collects the specific issues we encountered when bringing up Drone CI on VMStation, exact commands and directories used to fix them, and the validation script to confirm correct configuration.

Root causes encountered
-----------------------
1. HostPath permission/ownership: Drone stores sqlite data on a hostPath (/mnt/storage/drone). The directory either didn't exist or was owned by root, causing Drone to fail to write.
2. Missing/empty Kubernetes Secret keys: The in-cluster Secret `drone-secrets` had empty `github-client-id` and `github-client-secret`, so Drone exited with "source code management system not configured".
3. Misconfigured DRONE_SERVER_HOST format: The secret value included the URL scheme (http://...), while Drone expects host:port in DRONE_SERVER_HOST and the scheme in DRONE_SERVER_PROTO.
4. Monitoring side-effects: promtail needed a writable /tmp (emptyDir) when containers run readOnlyRootFilesystem, and DNS (CoreDNS) instability affected Loki pushes.

Files & directories of interest
------------------------------
- ansible/group_vars/secrets.yml
  - Plaintext secret variables used by plays during debugging/initial setup.
  - Keys used: `drone_github_client_id`, `drone_github_client_secret`, `drone_rpc_secret`, `drone_server_host`.

- ansible/subsites/05-extra_apps.yaml
  - Playbook that validates and deploys Drone, MongoDB, and Kubernetes Dashboard.
  - Contains pre-check `Check if drone secrets are properly configured` and a task `Create drone secrets from vault variables`.

- ansible/plays/apply_drone_secrets.yml
  - Small helper play that idempotently applies `drone-secrets` from `ansible/group_vars/secrets.yml`.

- scripts/setup_drone_secrets.sh
  - Interactive helper that guides creation of GitHub OAuth and instructs editing `ansible/group_vars/secrets.yml`.

- scripts/validate_drone_config.sh
  - Full validation script for Drone (checks namespace, secret keys, pod health, logs, and service reachability).
  - Path: `scripts/validate_drone_config.sh`

- HostPath locations to check on nodes:
  - Drone data: /mnt/storage/drone
  - MongoDB data: /mnt/storage/mongodb
  - Local-path provisioner storage (node-specific): check the local-path provisioner `nodePathMap` in its logs or config; host path often under `/srv/...` on the provisioner node.

Exact commands used / recommended fixes
--------------------------------------
(These are the commands we used during troubleshooting; run on the control host unless noted)

1) Ensure hostPath exists and is owned by Drone's UID (1000)
```bash
# Run on the node that hosts the pod (example: homelab)
sudo mkdir -p /mnt/storage/drone
sudo chown -R 1000:1000 /mnt/storage/drone
sudo chmod -R 750 /mnt/storage/drone
```
Note: the playbook `ansible/subsites/05-extra_apps.yaml` includes an init Pod `drone-hostpath-init` that does this automatically when run from Ansible.

2) Apply secrets (idempotent) using the helper play (recommended)
```bash
ansible-playbook -i ansible/inventory.txt ansible/plays/apply_drone_secrets.yml
```
This play loads `ansible/group_vars/secrets.yml` and creates/updates the `drone-secrets` Secret in the `drone` namespace.

Alternative (kubectl one-liner) — runs locally and does not print secret values
```powershell
# PowerShell example (copy values from your group_vars file)
$y = Get-Content .\ansible\group_vars\secrets.yml -Raw
$cid  = [regex]::Match($y,'drone_github_client_id:\s*"(.*)"').Groups[1].Value
$csec = [regex]::Match($y,'drone_github_client_secret:\s*"(.*)"').Groups[1].Value
$rpc  = [regex]::Match($y,'drone_rpc_secret:\s*"(.*)"').Groups[1].Value
$host = [regex]::Match($y,'drone_server_host:\s*"(.*)"').Groups[1].Value
$manifest = @"
apiVersion: v1
kind: Secret
metadata:
  name: drone-secrets
  namespace: drone
type: Opaque
stringData:
  github-client-id: $cid
  github-client-secret: $csec
  rpc-secret: $rpc
  server-host: $host
"@
$manifest | kubectl apply -f -
```

3) Important: DRONE_SERVER_HOST must be host:port (no scheme)
- Example (in `ansible/group_vars/secrets.yml`):
```yaml
drone_server_host: "192.168.4.62:32002"
drone_rpc_secret: "<random-secret>"
```
- Keep DRONE_SERVER_PROTO set in the Deployment to `http` if you use HTTP.

4) Restart Drone after applying secrets
```bash
kubectl -n drone rollout restart deployment drone
kubectl -n drone get pods -n drone -o wide
kubectl -n drone logs -l app=drone --tail=200
```

5) Inspect Secret contents (shows base64; decode locally if needed)
```bash
kubectl -n drone get secret drone-secrets -o yaml
# Decode locally (example)
kubectl -n drone get secret drone-secrets -o jsonpath='{.data.github-client-id}' | base64 -d
```

Monitoring-specific fixes (brief)
--------------------------------
- promtail: add writable /tmp emptyDir to each promtail DaemonSet container when the container runs with readOnlyRootFilesystem.
  - Example kubectl patch used during troubleshooting:
```bash
kubectl -n monitoring patch daemonset loki-stack-promtail --type='json' -p '[{"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"promtail-tmp","emptyDir":{}}},{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"promtail-tmp","mountPath":"/tmp"}}]'
kubectl -n monitoring rollout restart daemonset loki-stack-promtail
```
- CoreDNS: restart if you see DNS lookups failing from pods
```bash
kubectl -n kube-system rollout restart deployment coredns
```

Validation
----------
Run the repository validation script for Drone to confirm configuration and runtime health:
```bash
# from repo root
gnu/bash scripts/validate_drone_config.sh
# or make executable and run:
chmod +x scripts/validate_drone_config.sh
./scripts/validate_drone_config.sh
```

The script performs the following checks:
- verifies `kubectl` availability
- verifies `drone` namespace and deployment exist
- checks `drone-secrets` presence and required keys (rpc-secret, github-client-id, github-client-secret, server-host)
- analyzes recent Drone logs for "source code management system not configured" and other errors
- tests Drone service endpoint reachability via nodePort

Post-validation next steps
-------------------------
- If the validation script flags placeholder values or missing keys, re-edit `ansible/group_vars/secrets.yml` and re-run the secrets play.
- If Drone logs still show SCM errors after secrets are present, re-check the GitHub OAuth app settings (Homepage URL and Authorization callback URL must match your Drone host and port) and confirm the client ID/secret are correct.

Appendix: Quick commands reference
---------------------------------
- Apply Drone secrets with Ansible:
  ansible-playbook -i ansible/inventory.txt ansible/plays/apply_drone_secrets.yml
- Apply Drone secrets with kubectl (PowerShell helper): see the PowerShell snippet above
- Restart Drone:
  kubectl -n drone rollout restart deployment drone
- View logs:
  kubectl -n drone logs -l app=drone --tail=200
- Validate Drone:
  ./scripts/validate_drone_config.sh

Document status
---------------
- This is a concise, operational doc capturing the fixes performed, the files of interest, exact commands used, and the validation script to re-run checks. Keep secrets.yml in vault for production.

