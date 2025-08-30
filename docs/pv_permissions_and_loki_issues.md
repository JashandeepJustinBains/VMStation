## PV permissions & Loki config: Grafana CrashLoopBackOff and Loki write errors

This mini doc explains two related issues encountered during a monitoring stack deployment: a Grafana CrashLoopBackOff caused by PVC/PV permissions, and a Loki StatefulSet crash caused by an invalid config field and a missing writable mount. The examples use placeholders like `<pvc-name-here>` and `<pv-hostpath-here>`; replace them with the values from your `kubectl` output.

### Checklist
- Summarize the failure mode and root cause.
- Show how to trace PVC → PV → hostPath.
- Provide safe remediation steps to fix ownership/permissions and SELinux labels.
- Provide Loki-specific fixes: remove invalid config entries and ensure the PVC is mounted at `/loki` for writeable storage.
- Verification commands to confirm recovery.

## 1) Grafana: CrashLoopBackOff due to PV permissions

Summary
- Grafana's init container performs chown/write operations on the data directory (typically mounted at `/var/lib/grafana`). If the underlying PV (hostPath for local-path provisioner) is owned by a UID/GID that doesn't permit these operations, the init container will fail with "Permission denied" and the pod will repeatedly enter CrashLoopBackOff.

Diagnosis steps
1. Find the Grafana pod and its PVC:

```bash
# namespace as used in your cluster
kubectl -n monitoring get pods -l app.kubernetes.io/name=grafana
kubectl -n monitoring describe pod <grafana-pod-name>

# find PVC used by the pod (from the pod or deployment manifest)
kubectl -n monitoring get pvc <pvc-name-here> -o yaml
kubectl get pv $(kubectl -n monitoring get pvc <pvc-name-here> -o jsonpath='{.spec.volumeName}') -o yaml
```

2. On the node that hosts the PV, inspect the hostPath (use the path from `pv.spec.hostPath.path`):

```bash
# run on the node where the PV hostPath lives (eg: masternode)
sudo stat -c 'UID:%u GID:%g MODE:%a' <pv-hostpath-here>
sudo ls -la <pv-hostpath-here>
```

Look for ownership that does not match Grafana's runtime UID (commonly `472`) or missing write bits.

Fix
- On the node that owns the hostPath, chown/chmod to the Grafana UID:GID and make sure permissions allow traversal and write:

```bash
# example: set ownership to Grafana runtime UID:GID (replace <grafana-uid> if different)
sudo chown -R <grafana-uid>:<grafana-uid> <pv-hostpath-here>
sudo chmod -R 755 <pv-hostpath-here>
```

If SELinux is enforced on that node, relabel the content:

```bash
getenforce   # should return Enforcing or Permissive/Disabled
# if Enforcing, set and restore context for container files
sudo semanage fcontext -a -t container_file_t "<pv-hostpath-here>(/.*)?" && sudo restorecon -R <pv-hostpath-here>
# or simply: sudo restorecon -R <pv-hostpath-here>
```

Recreate Grafana pod (init container will re-run):

```bash
kubectl -n monitoring rollout restart deployment <grafana-deployment-name>
# or delete the pod directly
kubectl -n monitoring delete pod <grafana-pod-name>
```

Verification

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=grafana
kubectl -n monitoring exec -n monitoring <grafana-pod-name> -- ls -ld /var/lib/grafana
kubectl -n monitoring exec -n monitoring <grafana-pod-name> -- sh -c 'touch /var/lib/grafana/.ok && echo ok || echo failed'
kubectl -n monitoring logs -n monitoring <grafana-pod-name> --since=5m
```

Expected: init container completes without Permission denied, main container becomes Running.

## 2) Loki: YAML schema error + read-only filesystem for /loki

Summary
- Two separate issues were observed:
  1. The Loki config (stored as a Secret `loki.yaml`) contained an invalid field (`max_retries`) that caused Loki to fail parsing its config and exit.
  2. Loki's container runs with `readOnlyRootFilesystem: true` and expects a writable directory at `/loki` for chunks and WAL — the StatefulSet originally only mounted the PVC at `/data`, not `/loki`, so Loki attempted to mkdir `/loki/chunks` and failed with "read-only file system".

Diagnosis steps

1. Check Loki pod logs for the parsing error and the later runtime errors:

```bash
kubectl -n monitoring logs loki-stack-0 --tail=200
```

2. Decode the Secret to review the `loki.yaml` configuration:

```bash
kubectl -n monitoring get secret loki-stack -o jsonpath='{.data.loki\\.yaml}' | base64 -d > /tmp/loki.yaml
sed -n '1,200p' /tmp/loki.yaml
```

If you see a YAML/validation error mentioning `max_retries` (or another unknown field), remove that field or replace with the correct schema for your Loki version.

Fix (config)

Edit and reapply the secret (example removes `max_retries` lines):

```bash
# edit /tmp/loki.yaml and remove any invalid keys like `max_retries:`
kubectl -n monitoring create secret generic loki-stack --from-file=loki.yaml=/tmp/loki.yaml --dry-run=client -o yaml | kubectl apply -f -
```

Fix (storage write path)

Ensure the StatefulSet mounts the same PVC at `/loki` (replace `<pvc-name-here>` and `<container-index>` as needed). Example `kubectl patch` (JSON patch) that appends a mount to the first container:

```bash
kubectl -n monitoring patch statefulset loki-stack --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"storage","mountPath":"/loki"}}]'
```

You can also replace the whole `volumeMounts` array to a canonical list (example shows the intent):

```bash
kubectl -n monitoring patch statefulset loki-stack --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/volumeMounts","value":[
    {"mountPath":"/tmp","name":"tmp"},
    {"mountPath":"/etc/loki","name":"config"},
    {"mountPath":"/data","name":"storage"},
    {"mountPath":"/loki","name":"storage"}
  ]}
]'
```

After patching, delete the failing pod to force recreation with the new mount:

```bash
kubectl -n monitoring delete pod loki-stack-0
```

Host ownership for Loki data

On the node that hosts the PV, ensure the hostPath is owned by Loki's runtime UID (example used `10001` in this environment):

```bash
sudo chown -R <loki-uid>:<loki-uid> <pv-hostpath-here>
sudo chmod -R 755 <pv-hostpath-here>
```

If SELinux is enforcing on the node, relabel similarly to Grafana.

Verification

```bash
kubectl -n monitoring get pods -l app.kubernetes.io/name=loki
kubectl -n monitoring logs loki-stack-0 --tail=200
kubectl -n monitoring exec -n monitoring loki-stack-0 -- sh -c 'touch /loki/.ok && echo write-ok || echo write-failed; ls -ld /loki'
kubectl -n monitoring exec -n monitoring loki-stack-0 -- curl -fsS http://127.0.0.1:3100/ready || echo not-ready
```

Expected: Loki starts without config parse errors, can write to `/loki` (touch succeeds), and readiness endpoint returns OK.

## Preventive recommendations

- When using hostPath-backed PVs (local-path provisioner) ensure an automation step sets ownership to the expected container UID or use an init/system that sets it at provision time.
- Prefer dynamic provisioners that support setting correct permissions or use a privileged init container in a controlled way (best avoided for security reasons) to set ownership.
- Always validate Secrets containing config files after upgrades; schema changes in upstream software can invalidate formerly-accepted keys.
- For clusters with SELinux nodes (RHEL/CentOS), include SELinux relabeling (semanage/restorecon) in your provisioning workflow for PV hostPaths.

## TL;DR

Grafana CrashLoopBackOff: init container failed because the hostPath backing the PVC was not writable/chownable by Grafana's runtime UID — fix with chown/chmod and SELinux relabel if needed.

Loki CrashLoopBackOff: first a config parse error (remove invalid keys like `max_retries`), then a runtime write failure because `/loki` was not mounted as a writable path — fix by mounting the storage PVC at `/loki` and ensuring host ownership matches the container UID.

---

If you want, I can also add an Ansible playbook under `ansible/plays/` that automates the hostPath chown/restorecon for all `local-path` PVs in the cluster (dry-run first). Reply and I will add it.
