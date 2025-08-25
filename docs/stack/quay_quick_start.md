# Quick Start: Red Hat Quay Integration

This guide helps you quickly integrate Red Hat Quay with your VMStation monitoring setup.

## Prerequisites

1. VMStation monitoring stack already deployed
2. Ansible configured with your inventory
3. (Optional) Quay.io account for private repositories

## Step 1: Configure Quay Integration

1. **Copy configuration template:**
   ```bash
   cp ansible/group_vars/all.yml.template ansible/group_vars/all.yml
   ```

2. **Edit configuration:**
   ```bash
   vim ansible/group_vars/all.yml
   ```
   
   Enable Quay metrics monitoring:
   ```yaml
   enable_quay_metrics: true
   ```

3. **If using private repositories, add credentials (encrypt with Ansible Vault):**
   ```bash
   ansible-vault edit ansible/group_vars/all.yml
   ```
   
   Add:
   ```yaml
   quay_username: "your_username"
   quay_password: "your_password"
   ```

## Step 2: Deploy Quay Integration

Run the Quay integration playbook:
```bash
ansible-playbook -i ansible/inventory.txt ansible/plays/setup_quay_integration.yaml
```

If using Ansible Vault:
```bash
ansible-playbook -i ansible/inventory.txt ansible/plays/setup_quay_integration.yaml --ask-vault-pass
```

## Step 3: Verify Integration

1. **Check Prometheus targets:**
   - Open http://192.168.4.63:9090/targets
   - Look for `quay_metrics` job

2. **View Quay dashboard:**
   - Open http://192.168.4.63:3000
   - Navigate to "Red Hat Quay Registry Metrics" dashboard

3. **Test registry access:**
   ```bash
   # On any node
   podman pull quay.io/podman/stable:latest
   ```

## Step 4: Using Quay for Your Images

### Public Repository (Free)
1. Create account at https://quay.io
2. Create public repository
3. Push images:
   ```bash
   podman tag local-image:latest quay.io/your-username/your-image:latest
   podman push quay.io/your-username/your-image:latest
   ```

### Update Playbooks to Use Quay Images
Replace local registry references:
```yaml
# Before
image: 192.168.4.63:5000/my-image:latest

# After  
image: quay.io/your-username/my-image:latest
```

## Benefits You'll Get

- ✅ **Monitoring**: Quay metrics in your existing Grafana dashboards
- ✅ **Reliability**: Enterprise-grade registry with high availability
- ✅ **Security**: Automated vulnerability scanning for your images
- ✅ **Backup**: Your images stored outside your homelab
- ✅ **Sharing**: Easy sharing of public images

## Free Tier Limitations

- Public repositories: Unlimited
- Private repositories: Limited (check Quay.io pricing)
- Build minutes: Limited per month
- Storage: Check current limits

## Cost Optimization Tips

1. **Use public repos** for non-sensitive images
2. **Keep local registry** for development/private images
3. **Use Quay** as backup/distribution for stable releases
4. **Monitor usage** with the new Grafana dashboard

## Troubleshooting

### Quay Metrics Not Appearing
- Verify `enable_quay_metrics: true` in `ansible/group_vars/all.yml`
- Check Prometheus targets page for errors
- Ensure network connectivity to quay.io

### Authentication Issues
- Verify credentials with: `podman login quay.io`
- Check Ansible Vault encryption is working
- Use `ansible-vault view ansible/group_vars/all.yml` to verify credentials

### Registry Configuration Issues
- Check `/etc/containers/registries.conf.d/additional-registries.conf` on nodes
- Test with: `podman pull quay.io/podman/stable:latest`
- Restart podman if needed: `sudo systemctl restart podman`

## Next Steps

1. **Explore Quay features** like automated builds and security scanning
2. **Create CI/CD pipelines** that push to both local and Quay registries
3. **Set up monitoring alerts** for Quay metrics in Prometheus
4. **Document your image tagging strategy** for hybrid registry usage