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

Cloudflare Tunnel (optional - pod-scoped sidecar)

This StatefulSet includes an optional `cloudflared` sidecar container that tunnels the Minecraft server through Cloudflare Tunnel. The tunnel runs **only inside the pod** and requires no host-level installation — credentials are stored in a Kubernetes Secret (namespace-scoped, pod-scoped).

### Why use Cloudflare Tunnel?
- **No port forwarding needed**: Tunnel is outbound-only; no need to open router ports or expose your home IP.
- **Identity-based access** (optional): Use Cloudflare Access policies to require authentication before connecting.
- **Pod-scoped isolation**: Tunnel credentials exist only in the `default` namespace and only the Minecraft pod can mount them.

### Setup instructions

#### Step 1: Generate tunnel credentials on the homelab node

SSH to the homelab and generate the tunnel:

```bash
ssh jashandeepjustinbains@192.168.4.62

# Install cloudflared if not present
sudo curl -L --output /usr/local/bin/cloudflared \
  https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
sudo chmod +x /usr/local/bin/cloudflared

# Login to Cloudflare (opens browser for OAuth)
cloudflared tunnel login

# Create a tunnel named 'my-minecraft-tunnel'
cloudflared tunnel create my-minecraft-tunnel

# This outputs:
# Tunnel credentials written to /home/jashandeepjustinbains/.cloudflared/<tunnel-id>.json
# Tunnel <tunnel-id> created with name my-minecraft-tunnel

# List your tunnels
cloudflared tunnel list

exit
```

#### Step 2: Create Kubernetes secret from the tunnel credentials

From your control machine (masternode or workstation with kubectl access), stream the credentials from homelab to kubectl:

```bash
# Replace <tunnel-id> with the ID from step 1
ssh jashandeepjustinbains@192.168.4.62 \
  'cat ~/.cloudflared/<tunnel-id>.json' \
  | kubectl -n default create secret generic cloudflared-credentials \
    --from-file=credentials.json=/dev/stdin

# Verify the secret was created
kubectl -n default get secret cloudflared-credentials
```

#### Step 3: Deploy the Minecraft server

```bash
# From your repo root
./deploy.sh minecraft

# Watch the pod start
kubectl get pod -l app=minecraft -w

# Check logs
kubectl logs minecraft-0 -c minecraft -f
```

#### Step 4: Configure the tunnel ingress in Cloudflare dashboard

In **Cloudflare Zero Trust → Networks → Tunnels → my-minecraft-tunnel**:

1. Click **Configure** to add a public hostname or TCP rule.
2. For TCP (raw Minecraft):
   - **Public hostname**: `minecraft.yourdomain.com` (or use a subdomain)
   - **Protocol**: TCP
   - **TTL**: Auto
   - **Service**: `localhost:25565`
3. Save.

Alternative: If using Cloudflare Spectrum (plan-dependent), add a TCP ingress rule:
```
minecraft.yourdomain.com:25565 → tcp://127.0.0.1:25565
```

#### Step 5: Share the tunnel hostname with friends

Give your friends the tunnel address (e.g., `minecraft.yourdomain.com:25565`) and they can connect via Minecraft client directly.

#### Step 6: Verify the tunnel is active

```bash
# Check cloudflared sidecar logs
kubectl logs minecraft-0 -c cloudflared

# Expected output:
# Tunnel registered with connection ID <id>
# Connection established successfully
```

### Monitoring & troubleshooting

**Check tunnel status in Cloudflare dashboard:**
- Navigate to **Tunnels** and look for "Connected" status.

**If pod fails to start:**
```bash
# Check secret exists
kubectl get secret cloudflared-credentials -n default

# Inspect pod events
kubectl describe pod minecraft-0
```

**If tunnel disconnects:**
- Check cloudflared logs: `kubectl logs minecraft-0 -c cloudflared`
- Restart pod: `kubectl delete pod minecraft-0`

### Security & best practices

- **Credential rotation**: Regenerate tunnel credentials periodically and update the secret.
- **Access policies** (optional): In Cloudflare Zero Trust, add "Access" policies to require email/SAML authentication.
- **Read-only mounts**: The secret is mounted read-only at `/etc/cloudflared/credentials.json`; pod cannot modify credentials.
- **No host-level exposure**: Tunnel runs only inside the pod; homelab host is not affected.

### Alternative: Host-level cloudflared (not recommended)

If you prefer to run `cloudflared` as a systemd service on the homelab host instead of the sidecar:

1. Install and configure cloudflared on the homelab host (as shown in Step 1).
2. Create a systemd service to run the tunnel persistently.
3. Disable the sidecar in the StatefulSet (remove or comment out the `cloudflared` container).

However, this approach exposes credentials to the host filesystem and is not pod-isolated. The sidecar approach (above) is recommended.
