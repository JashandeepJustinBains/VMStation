# Cloudflare Tunnel (Zero Trust) Quickstart

This guide explains how to set up a free Cloudflare Tunnel (Zero Trust) to securely expose your self-hosted applications to the internet.

---

## 1. What is Cloudflare Tunnel?
Cloudflare Tunnel (formerly Argo Tunnel) lets you securely expose local services to the internet without opening firewall ports. It uses Cloudflare's global network and Zero Trust features for authentication and access control.

---

## 2. Prerequisites
- Free Cloudflare account
- Domain managed by Cloudflare (can use a subdomain)
- Access to your server (MiniPC, T3500, R430)

---

## 3. Install Cloudflare Tunnel (cloudflared)
```bash
wget -O cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
sudo mv cloudflared /usr/local/bin/
sudo chmod +x /usr/local/bin/cloudflared
cloudflared --version
```

---

## 4. Authenticate cloudflared with Cloudflare
```bash
cloudflared tunnel login
```
- This opens a browser to authenticate with your Cloudflare account.

---

## 5. Create and Run a Tunnel
```bash
cloudflared tunnel create mytunnel
cloudflared tunnel route dns mytunnel app.example.com
cloudflared tunnel run mytunnel --url http://localhost:8080
```
- Replace `app.example.com` with your domain/subdomain.
- Replace `http://localhost:8080` with your app's local address.

---

## 6. Zero Trust Access (Optional)
- In Cloudflare dashboard, go to Zero Trust > Access > Applications.
- Add your app and configure authentication (Google, GitHub, etc.) for free.

---

## 7. Tips
- You can run multiple tunnels for different apps.
- No need to open inbound firewall ports.
- Free plan supports unlimited tunnels and users, with some feature limits.

---

## References
- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [Zero Trust Access](https://developers.cloudflare.com/cloudflare-one/identity/)
