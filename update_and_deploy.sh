#!/bin/bash

# Fetch latest changes from remote
git fetch --all
git pull --ff-only

# Make deploy.sh executable
chmod +x ./ansible/deploy.sh

# Run the deploy script (site playbook)
./ansible/deploy.sh
