# Printer Ops — Deployment instructions

This directory contains manifests for the Brother "brother-gateway" service and supporting storage.

Goal
- Deploy the brother-gateway Deployment so it schedules to the storage node and uses the existing PVCs.

Recommended (non-destructive) steps
1) From the repository root on your machine:

   cd /opt/vmstation-org/consolidated_update
   git fetch vmstation --prune
   git switch printer-ops-v1
   git pull vmstation printer-ops-v1

2) Verify required namespaced resources exist in `default`:

   kubectl get pvc -n default
   kubectl get configmap printers-hosts-config -n default
   kubectl get configmap scan-convert-scripts -n default

   - `paperless-input-pvc` and `scan-storage-pvc` should be Bound.
   - If the ConfigMaps are missing, create them from the operator files or copy them from the repo.

3) Apply the PVC manifest (safe if not present):

   kubectl apply -f manifests/storage/pvc-paperless-input.yaml

4) Apply the Deployment into the `default` namespace (without moving PVCs/ConfigMaps):

   # apply by rewriting the manifest's namespace on the fly
   kubectl apply -f <(sed 's/namespace: printer-ops/namespace: default/' manifests/printer-ops/brother-gateway-deployment.yaml)

   # If you prefer to keep the file unchanged, you can patch the current default deployment instead of applying a new file:
   # kubectl patch deployment brother-gateway -n default --type='json' -p='[{"op":"replace","path":"/spec/template/spec/nodeSelector","value":{"vmstation/role":"storage"}}]'

5) Scale down or delete any old deployment in `default` to avoid conflict (if present):

   kubectl scale deployment brother-gateway -n default --replicas=0 || true
   kubectl delete deployment brother-gateway -n default || true

6) Watch rollout and pod scheduling:

   kubectl rollout status deployment/brother-gateway -n default
   kubectl get pods -n default -o wide

Troubleshooting
- If the Pod stays `Pending`:
  - Describe the pod to see why:
    kubectl describe pod -n default $(kubectl get pods -n default -o jsonpath='{.items[?(@.metadata.labels.app=="brother-gateway")].metadata.name}')
  - Check events:
    kubectl get events -n default --sort-by='.lastTimestamp' | tail -n 50
  - Confirm node labels and taints:
    kubectl get nodes --show-labels
    kubectl describe node <node-name>

Common causes
- NodeSelector mismatch: manifests use `vmstation/role: storage` which matches the storage node label `vmstation/role=storage`.
- Missing/namespace-mismatched ConfigMaps or PVCs: ensure they exist in the same namespace as the Deployment.

Repository notes
- The `printer-ops-v1` branch contains:
  - `manifests/printer-ops/brother-gateway-deployment.yaml` — deployment manifest (namespace: printer-ops). Use the sed shortcut above to apply into `default`.
  - `manifests/storage/pvc-paperless-input.yaml` — PVC manifest (10Gi, manual)

Security / cleanup
- Do not store secrets or admin passwords in plaintext in the repo. The sample manifest contains a placeholder CUPS_ADMIN_PASSWORD — replace it with a secret/secretRef if used in production.

If you want, I can:
- Commit a version of `brother-gateway-deployment.yaml` that targets `default` permanently, or
- Create a small `manifests/printer-ops/README.md` (this file) with additional per-environment notes.

Reply with one of:
- "Apply now" — I will apply the default manifest into the cluster for you (need cluster access). (Note: I can only push repo changes; I cannot run kubectl on your machine.)
- "Commit default deployment" — I will commit a version of the deployment with `namespace: default` to the `printer-ops-v1` branch.
