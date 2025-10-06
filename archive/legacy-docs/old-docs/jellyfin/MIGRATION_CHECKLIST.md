# Jellyfin Podman to Kubernetes HA Migration Checklist

## Pre-Migration Assessment

### ✅ Current Environment Check
- [ ] Verify existing Podman Jellyfin is running: `podman ps | grep jellyfin`
- [ ] Document current Jellyfin URL: `http://192.168.4.61:8096`
- [ ] Check media library locations: `ls -la /mnt/media`
- [ ] Verify config directory: `ls -la /mnt/jellyfin-config`
- [ ] Note current user count and streaming patterns
- [ ] Document any custom transcoding settings
- [ ] Backup current configuration: `cp -r /mnt/jellyfin-config /backup/jellyfin-config-backup`

### ✅ Infrastructure Readiness
- [ ] Kubernetes cluster is running: `kubectl get nodes`
- [ ] Storage node has available resources: `free -h` (should show >2GB available)
- [ ] Hardware acceleration devices present: `ls -la /dev/dri/`
- [ ] Metrics server available: `kubectl top nodes`
- [ ] Monitoring stack operational: `kubectl get pods -n monitoring`

## Migration Steps

### Phase 1: Deploy Kubernetes Version (Parallel)

1. **Deploy Jellyfin HA**
   ```bash
   # Quick deployment
   ./deploy_jellyfin.sh
   
   # OR manual deployment
   ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_jellyfin.yaml
   ```
   - [ ] Deployment completed without errors
   - [ ] Pods are running: `kubectl get pods -n jellyfin`
   - [ ] Services are accessible: `kubectl get svc -n jellyfin`

2. **Initial Validation**
   ```bash
   # Run validation script
   ./scripts/validate_jellyfin_ha.sh
   ```
   - [ ] All Kubernetes resources created successfully
   - [ ] Persistent volumes bound correctly
   - [ ] Service endpoints responding
   - [ ] HPA configured and metrics available

### Phase 2: Configuration & Testing

3. **Access New Jellyfin Instance**
   - [ ] Connect to new URL: `http://192.168.4.63:30096`
   - [ ] Complete initial setup wizard (if needed)
   - [ ] Add media libraries (should auto-detect existing media)
   - [ ] Configure transcoding settings for hardware acceleration
   - [ ] Test user authentication/access

4. **Performance Testing**
   - [ ] Test single stream (1080p content)
   - [ ] Verify hardware acceleration is working
   - [ ] Test multiple concurrent streams (2-3 users)
   - [ ] Confirm auto-scaling triggers: `kubectl get hpa -n jellyfin -w`
   - [ ] Verify session affinity during scaling
   - [ ] Test large file upload (if used)

5. **User Acceptance Testing**
   - [ ] Test from each family device (TV, mobile, tablet, laptop)
   - [ ] Verify all existing users can access content
   - [ ] Test different content types (movies, TV shows, music)
   - [ ] Confirm remote access works (if enabled)
   - [ ] Test client apps (Jellyfin mobile app, web browser)

### Phase 3: Monitoring & Optimization

6. **Monitoring Setup**
   - [ ] Access Grafana dashboard: `http://192.168.4.63:30300`
   - [ ] Verify Jellyfin metrics are being collected
   - [ ] Set up any custom alerts (optional)
   - [ ] Document normal resource usage patterns

7. **Performance Optimization**
   - [ ] Adjust HPA thresholds if needed: `kubectl edit hpa jellyfin-hpa -n jellyfin`
   - [ ] Fine-tune resource limits if required: `kubectl edit deployment jellyfin -n jellyfin`
   - [ ] Optimize transcoding settings based on usage
   - [ ] Configure quality profiles for different devices

### Phase 4: Migration Completion

8. **Final Validation**
   - [ ] Run comprehensive test with all family members
   - [ ] Verify auto-scaling works correctly under load
   - [ ] Test failover scenarios (restart pods)
   - [ ] Confirm session persistence across scaling events
   - [ ] Validate backup/restore procedures

9. **Update Access Points**
   - [ ] Update bookmarks to new URL: `http://192.168.4.63:30096`
   - [ ] Update smart TV Jellyfin app server settings
   - [ ] Update mobile app connections
   - [ ] Notify family members of new URL (if different)
   - [ ] Update any automation scripts or integrations

10. **Legacy Cleanup**
    ```bash
    # Stop old Podman container (when confident in K8s version)
    ssh 192.168.4.61 'podman stop jellyfin'
    
    # Optional: Remove old container
    ssh 192.168.4.61 'podman rm jellyfin'
    
    # Optional: Remove old service files
    ssh 192.168.4.61 'rm -f /etc/systemd/system/jellyfin.service'
    ```
    - [ ] Stop Podman Jellyfin container
    - [ ] Remove container (optional, can keep as backup)
    - [ ] Clean up old service files
    - [ ] Update firewall rules if needed

## Post-Migration Monitoring

### Week 1: Initial Monitoring
- [ ] Monitor daily resource usage patterns
- [ ] Track auto-scaling events and frequency
- [ ] Verify no streaming interruptions during scaling
- [ ] Check for any error logs: `kubectl logs -n jellyfin -l app=jellyfin`

### Week 2-4: Optimization Period
- [ ] Fine-tune scaling thresholds based on usage patterns
- [ ] Optimize resource allocations if needed
- [ ] Document peak usage times and scaling behavior
- [ ] Adjust session affinity timeout if needed

### Ongoing Maintenance
- [ ] Weekly resource usage review
- [ ] Monthly container image updates
- [ ] Quarterly backup verification
- [ ] Annual configuration review

## Rollback Plan (If Needed)

If issues arise during migration:

1. **Immediate Rollback**
   ```bash
   # Start old Podman container
   ssh 192.168.4.61 'podman start jellyfin'
   
   # Verify it's accessible
   curl -I http://192.168.4.61:8096
   ```

2. **Kubernetes Cleanup**
   ```bash
   # Remove Kubernetes deployment (optional)
   kubectl delete namespace jellyfin
   ```

3. **Restore Access**
   - Update client connections back to `http://192.168.4.61:8096`
   - Verify all users can access content
   - Document issues for later resolution

## Success Criteria

✅ **Migration is successful when:**
- [ ] All family members can access media content without interruption
- [ ] Auto-scaling responds correctly to usage patterns
- [ ] Streaming quality is maintained or improved
- [ ] Resource usage stays within system limits (8GB RAM)
- [ ] No service downtime during normal operation
- [ ] Hardware acceleration is working for transcoding
- [ ] Monitoring provides visibility into system performance

## Contact & Support

- **Validation Scripts**: `./scripts/validate_jellyfin_ha.sh`
- **Logs**: `kubectl logs -n jellyfin -l app=jellyfin`
- **Events**: `kubectl get events -n jellyfin`
- **Documentation**: `docs/jellyfin/JELLYFIN_HA_DEPLOYMENT.md`

Remember: The Kubernetes version runs parallel to Podman during migration, so you always have a fallback option!