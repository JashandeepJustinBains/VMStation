#!/bin/bash

# Fetch latest changes from remote
cd /opt/vmstation
git fetch
git pull

# Make deploy.sh executable
chmod +x ./ansible/deploy.sh

# Run the deploy script
./ansible/deploy.sh
