#!/bin/bash

#!/bin/bash

# Change to the repository root (location of this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"/.. || exit 1

# Fetch latest changes from remote
git fetch --all
git pull --ff-only

# Make deploy.sh executable
chmod +x ./ansible/deploy.sh

# Run the deploy script (site playbook)
./ansible/deploy.sh

# Run the monitoring validation play locally on the monitoring node (if present)
if [ -f ./ansible/plays/monitoring_validation.yaml ]; then
	echo "Running monitoring validation play..."
	ansible-playbook -i ./ansible/inventory.txt ./ansible/plays/monitoring_validation.yaml
else
	echo "No monitoring_validation.yaml found; skipping validation."
fi
