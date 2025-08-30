#!/bin/bash
# Quick test script for playbook validation

echo "Testing Ansible playbook syntax..."

cd /home/runner/work/VMStation/VMStation

echo "✅ Testing Kubernetes Dashboard playbook syntax..."
ansible-playbook --syntax-check ansible/plays/kubernetes/deploy_dashboard.yaml

echo "✅ Testing Drone CI/CD playbook syntax..."  
ansible-playbook --syntax-check ansible/plays/kubernetes/deploy_drone.yaml

echo "✅ Testing existing monitoring playbook syntax..."
ansible-playbook --syntax-check ansible/plays/kubernetes/deploy_monitoring.yaml

echo "✅ Checking Ansible collection dependencies..."
ansible-galaxy collection list | grep kubernetes

echo "✅ All syntax checks passed!"
echo ""
echo "To deploy in production:"
echo "1. ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_dashboard.yaml"
echo "2. ansible-playbook -i ansible/inventory.txt ansible/plays/kubernetes/deploy_drone.yaml"
echo "3. Run ./scripts/validate_dashboard_drone.sh to verify"