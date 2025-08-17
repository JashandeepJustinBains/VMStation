#!/bin/bash

# Run the full site playbook
ansible-playbook -i ./ansible/inventory.txt --vault-password-file ~/.vault_pass.txt ./ansible/plays/site.yaml
# ansible-playbook -i ./ansible/inventory.txt ./ansible/plays/site.yaml