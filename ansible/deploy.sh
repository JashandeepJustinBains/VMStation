#!/bin/bash
# filepath: f:\VMStation\ansible\deploy.sh

# Install required Ansible collections
ansible-galaxy collection install community.kubernetes

# Run the full site playbook
ansible-playbook -i ./inventory ./plays/site.yaml