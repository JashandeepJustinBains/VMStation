# Minecraft on homelab (ansible/files/minecraft)

This folder contains Kubernetes manifests and a small playbook to deploy a Minecraft server on a single RHEL10 homelab node.

Files:
- `minecraft-configmap.yaml` - ConfigMap containing `server.properties`.
- `minecraft-pv-pvc.yaml` - `PersistentVolume` (hostPath `/srv/minecraft-data`) and `PersistentVolumeClaim`.
- `minecraft-statefulset.yaml` - `StatefulSet` using `itzg/minecraft-server` image. Uses `hostNetwork: true` for simple NAT/port-forwarding.

Quick notes:
- By default the server `TYPE` is set to `FORGE` (modded). Change to `VANILLA` for a stock server or `FABRIC` for Fabric-based mods.
- If you have a server-side modpack ZIP available over HTTP(S), set `MODPACK_URL` in the StatefulSet env to let the container auto-install it.
- Alternatively pre-populate `/srv/minecraft-data` on the homelab node with the server files (world, `mods/`, `server.jar`, `eula.txt`).

Deploy steps (on control-plane with `kubectl` configured):

1. Prepare host path on homelab node (run on homelab node):

```powershell
# on homelab RHEL10 as root or via sudo
mkdir -p /srv/minecraft-data
chown 1000:1000 /srv/minecraft-data
```

2. Apply manifests from the repo root:

```powershell
kubectl apply -f ansible/files/minecraft/minecraft-configmap.yaml
kubectl apply -f ansible/files/minecraft/minecraft-pv-pvc.yaml
kubectl apply -f ansible/files/minecraft/minecraft-statefulset.yaml
```

3. Open firewall on the homelab node to allow Minecraft traffic:

```powershell
sudo firewall-cmd --permanent --add-port=25565/tcp
sudo firewall-cmd --reload
```

4. Forward your router public port TCP 25565 to the homelab node IP (e.g. 192.168.4.62:25565).

Testing & logs:

```powershell
kubectl get pods -l app=minecraft -w
kubectl logs -l app=minecraft --tail=200
```

Modpack guidance:
- If your friends will use a launcher that supports modpacks (CurseForge/FTB/Technic), ensure you have the server-side pack (not the client-only package). Most modpack providers offer a dedicated "server" download.
- Using `MODPACK_URL` is easiest: host the server zip somewhere reachable and set the env in the StatefulSet. The container will download and extract to `/data` on first run.
- If the pack requires large downloads, it's often faster to prepare the `/srv/minecraft-data` directory offline and copy it to the homelab node before starting.

Backups & maintenance:
- Back up `/srv/minecraft-data` regularly (worlds and mods can become corrupted).
- For multi-node or production usage, consider removing `hostNetwork: true` and exposing via NodePort/LoadBalancer (MetalLB) and use dynamic storage class instead of hostPath.

Node scheduling:
- **Pinned to homelab (inventory label):** This StatefulSet now includes a `nodeSelector: { vmstation.io/role: compute }` so the pod will schedule onto nodes labeled as `compute` in the repository inventory (your `homelab` node is labeled this way by Kubespray). The label originates from `ansible/inventory/hosts` where `homelab` has `node_labels` including `vmstation.io/role=compute`.
- **Check node labels:** To verify a node's labels run:

```powershell
kubectl get nodes --show-labels
kubectl describe node <node-name> | sed -n '/Labels:/,/Annotations:/p'
```

- **Choose a different node:** If you want the server on another node, either:
	- change the `nodeSelector` in `ansible/files/minecraft/minecraft-statefulset.yaml` to match a different label key/value present on the desired node, or
	- use `nodeName: <node-name>` in the pod spec for a hard pin (not recommended for portability), or
	- use `nodeAffinity` to express soft/preferred scheduling rules.

- **Example:** to pin to a node labelled `vmstation.io/role=storage` change the StatefulSet `nodeSelector` to:

```yaml
nodeSelector:
	vmstation.io/role: storage
```

- **Caveats:** If the label you reference does not exist on any ready node, the pod will stay Pending. After changing scheduling rules, re-apply the StatefulSet (`kubectl apply -f ...`) and watch `kubectl get pods -w` for scheduling decisions.

Cloudflare Tunnel (optional - sidecar)
-- If you want to expose the Minecraft server through Cloudflare Tunnel for Identity-based access and no inbound router ports, this StatefulSet includes a `cloudflared` sidecar which expects a Kubernetes Secret named `cloudflared-credentials` containing your tunnel credentials.

Quick steps to enable the tunnel (operator provides credentials):

1. Create the Kubernetes secret on the cluster (replace path to your credentials JSON):

```powershell
kubectl -n default create secret generic cloudflared-credentials \
	--from-file=credentials.json=/path/to/<your-tunnel-credentials>.json
```

2. In the Cloudflare Zero Trust dashboard create a Tunnel named `my-minecraft-tunnel` and add a TCP ingress rule or configure a hostname that maps to the tunnel and supports TCP/Spectrum if required by your plan. The sidecar runs:

```
cloudflared tunnel run --no-autoupdate --credentials-file /etc/cloudflared/credentials.json my-minecraft-tunnel --url tcp://127.0.0.1:25565
```

3. Apply the manifests (the StatefulSet already contains the sidecar and will mount the secret):

```powershell
kubectl apply -f ansible/files/minecraft/minecraft-configmap.yaml
kubectl apply -f ansible/files/minecraft/minecraft-pv-pvc.yaml
kubectl apply -f ansible/files/minecraft/minecraft-statefulset.yaml
```

Notes & caveats:
- Cloudflare HTTP Access is meant for web apps; proxying raw TCP (Minecraft) requires Cloudflare Tunnel TCP support or Spectrum (plan-dependent). Verify your Cloudflare plan supports TCP ingress with Access enforcement.
- Keep the tunnel credentials secret; do not commit them to Git. Use Kubernetes Secrets as shown.
- If you prefer not to run the sidecar, you can run `cloudflared` on the homelab host as a systemd service and point it to `127.0.0.1:25565` instead.
- Monitor `cloudflared` logs and rotate credentials periodically.
