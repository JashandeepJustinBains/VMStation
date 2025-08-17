#!/bin/bash

# Run the full site playbook
ansible-playbook -i ./ansible/inventory.txt ./ansible/plays/site.yaml