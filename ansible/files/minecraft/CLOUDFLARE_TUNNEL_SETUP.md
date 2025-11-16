# Cloudflare Tunnel Setup for Minecraft

This guide covers setting up Cloudflare Tunnel to expose your Minecraft server securely without opening inbound ports on your router.

## Prerequisites

- A Cloudflare account with Zero Trust access (Cloudflare Tunnel is available on most plans).
- Access to Cloudflare Zero Trust dashboard at https://one.dash.cloudflare.com/.
- kubectl configured to access your Kubernetes cluster.

## Two Methods: Token vs. Credentials File

### Method 1: Token-Based (Quick & Simple)

Recommended for quick setup. Tokens are short-lived and easier to rotate.

#### Step 1: Generate a Token in Cloudflare Zero Trust

1. Go to https://one.dash.cloudflare.com/ → **Access** → **Tunnels**.
2. Click **Create a tunnel** and name it (e.g., `my-minecraft-tunnel`).
3. Select **Kubernetes** as the environment (or any, this is for reference).
4. In the next step, copy the **tunnel token** (a long alphanumeric string starting with `ey...`).
5. Save the token securely — do not commit it to Git.

#### Step 2: Create the Kubernetes Secret

```powershell
kubectl -n default create secret generic cloudflared-token \
  --from-literal=token='YOUR_CLOUDFLARED_TOKEN_HERE'
```

Replace `YOUR_CLOUDFLARED_TOKEN_HERE` with the token you copied.

#### Step 3: Deploy the Minecraft Manifests

The StatefulSet sidecar will automatically use the token if present. Deploy normally:

```powershell
kubectl apply -f ansible/files/minecraft/minecraft-configmap.yaml
kubectl apply -f ansible/files/minecraft/minecraft-pv-pvc.yaml
kubectl apply -f ansible/files/minecraft/minecraft-statefulset.yaml
```

#### Step 4: Verify the Tunnel Connection

```powershell
# Watch for the pod to start and the cloudflared sidecar to connect
kubectl get pods -l app=minecraft -w

# Check cloudflared logs to confirm tunnel is active
kubectl logs -l app=minecraft -c cloudflared --tail=50
```

You should see output like:
```
2025-11-16T16:00:00Z INF Starting tunnel tunnel=my-minecraft-tunnel
2025-11-16T16:00:01Z INF Registered tunnel connection
```

#### Step 5: Configure the Cloudflare Tunnel Ingress

1. In Cloudflare Zero Trust dashboard → **Access** → **Tunnels** → select your tunnel.
2. Go to **Public Hostnames** tab.
3. Add a route:
   - **Subdomain**: `minecraft` (or your choice)
   - **Domain**: `example.com` (your domain)
   - **Type**: `TCP`
   - **URL**: `localhost:25565`
4. Save.

Your friends can now connect to `minecraft.example.com:25565` in their Minecraft client.

---

### Method 2: Credentials File (Persistent Named Tunnel)

Recommended for long-running, managed tunnels. Better for production.

#### Step 1: Generate Credentials File

1. Install `cloudflared` locally (https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/).
2. Run:
   ```bash
   cloudflared tunnel create my-minecraft-tunnel
   ```
3. This creates a named tunnel and stores credentials at `~/.cloudflared/<tunnel-id>.json`.
4. Locate the credentials JSON file and keep it secure.

#### Step 2: Create the Kubernetes Secret

```powershell
kubectl -n default create secret generic cloudflared-credentials \
  --from-file=credentials.json=/path/to/<tunnel-id>.json
```

#### Step 3: Deploy the Minecraft Manifests

The StatefulSet sidecar will use the credentials file if present (and no token secret exists). Deploy normally:

```powershell
kubectl apply -f ansible/files/minecraft/minecraft-configmap.yaml
kubectl apply -f ansible/files/minecraft/minecraft-pv-pvc.yaml
kubectl apply -f ansible/files/minecraft/minecraft-statefulset.yaml
```

#### Step 4: Verify and Configure Ingress

Same as Method 1, steps 4-5 above.

---

## Switching Between Methods

The StatefulSet checks for both methods in this order:
1. **Token** (prefers if secret `cloudflared-token` exists).
2. **Credentials file** (uses if secret `cloudflared-credentials` exists).

To switch:
- Delete the old secret and create the new one.
- The pod will restart and pick up the new auth method.

Example (switch from token to credentials):
```powershell
kubectl delete secret cloudflared-token
kubectl create secret generic cloudflared-credentials \
  --from-file=credentials.json=/path/to/<tunnel-id>.json
kubectl delete pod minecraft-0  # Force pod restart
```

---

## Managing Access with Cloudflare Access

If you want to add identity-based access (e.g., require login via Google/GitHub):

1. In Cloudflare Zero Trust dashboard → **Access** → **Applications**.
2. Create a new application:
   - **Application name**: `minecraft`
   - **Application domain**: `minecraft.example.com` (must match your tunnel ingress).
3. Set up policies (e.g., require users from your domain, or specific email addresses).
4. Save.

Now friends must authenticate before connecting to the Minecraft server.

---

## Troubleshooting

### Pod won't start / cloudflared exits immediately

- Check the secret exists:
  ```powershell
  kubectl get secret cloudflared-token
  kubectl get secret cloudflared-credentials
  ```
- Check pod logs:
  ```powershell
  kubectl logs minecraft-0 -c cloudflared
  ```
- Verify token/credentials are valid and not expired.

### Tunnel shows "disconnected" in Cloudflare dashboard

- Confirm pod is running:
  ```powershell
  kubectl get pods -l app=minecraft
  ```
- Check for network issues or high memory usage:
  ```powershell
  kubectl describe pod minecraft-0
  ```
- Restart the pod:
  ```powershell
  kubectl delete pod minecraft-0
  ```

### Friends cannot connect

- Verify the public hostname is configured in Cloudflare (check dashboard → Tunnels → Public Hostnames).
- Test locally first:
  ```powershell
  # From your cluster, try connecting via the tunnel
  nc -zv minecraft.example.com 25565
  ```
- Check Minecraft server logs:
  ```powershell
  kubectl logs minecraft-0 -c minecraft --tail=100
  ```

---

## Security Best Practices

- **Rotate tokens/credentials regularly**: Generate new tokens/credentials in Cloudflare and update the secret.
- **Limit secret access**: Use Kubernetes RBAC to restrict who can read the secret.
- **Monitor tunnel**: Set up alerts if the tunnel disconnects.
- **Use Cloudflare Access policies**: Require authentication for sensitive use cases.
- **Pin cloudflared image**: Use a specific digest instead of `latest` to avoid unexpected updates.

---

## Additional Resources

- Cloudflare Tunnel docs: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
- Cloudflare Access: https://developers.cloudflare.com/cloudflare-one/identity/
- TCP routing with Spectrum: https://developers.cloudflare.com/spectrum/

