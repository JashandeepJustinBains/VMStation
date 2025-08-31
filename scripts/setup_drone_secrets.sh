#!/bin/bash

# Drone CI Secrets Setup Helper
# This script helps users configure GitHub OAuth credentials for Drone CI

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BOLD}=== Drone CI Secrets Setup Helper ===${NC}"
echo "This script will help you configure GitHub OAuth credentials for Drone CI"
echo ""

SECRETS_FILE="ansible/group_vars/secrets.yml"

# Check if secrets file exists
if [ ! -f "$SECRETS_FILE" ]; then
    echo -e "${RED}✗ Secrets file not found: $SECRETS_FILE${NC}"
    echo "Creating basic secrets file..."
    cp ansible/group_vars/secrets.yml.example "$SECRETS_FILE"
    echo -e "${GREEN}✓ Created secrets file from example${NC}"
fi

echo -e "${BLUE}Current secrets file status:${NC}"
if grep -q "REPLACE_WITH_" "$SECRETS_FILE"; then
    echo -e "${YELLOW}⚠ Found placeholder values in secrets file${NC}"
    NEEDS_CONFIGURATION=true
else
    echo -e "${GREEN}✓ No obvious placeholder values found${NC}"
    NEEDS_CONFIGURATION=false
fi

echo ""
echo -e "${BOLD}=== GitHub OAuth Setup Instructions ===${NC}"
echo ""
echo "1. Create GitHub OAuth Application:"
echo "   Go to: https://github.com/settings/applications/new"
echo ""
echo "2. Fill in these values:"
echo "   - Application name: VMStation Drone CI"
echo "   - Homepage URL: http://192.168.4.62:32001"
echo "   - Authorization callback URL: http://192.168.4.62:32001/login"
echo ""
echo "3. After creating the app, GitHub will show you:"
echo "   - Client ID (looks like: 1234567890abcdef1234)"
echo "   - Client Secret (click 'Generate a new client secret')"
echo ""

if [ "$NEEDS_CONFIGURATION" = true ]; then
    echo -e "${YELLOW}Would you like to configure the secrets interactively? (y/n):${NC}"
    read -r response
    
    if [[ "$response" =~ ^[Yy] ]]; then
        echo ""
        echo "Please enter your GitHub OAuth credentials:"
        
        echo -n "GitHub Client ID: "
        read -r client_id
        
        echo -n "GitHub Client Secret: "
        read -r -s client_secret
        echo ""
        
        # Generate RPC secret
        rpc_secret=$(openssl rand -hex 16)
        echo "Generated RPC secret: $rpc_secret"
        
        echo -n "Server host (e.g., 192.168.4.62:32001): "
        read -r server_host
        
        # Update secrets file
        sed -i "s/REPLACE_WITH_GITHUB_CLIENT_ID/$client_id/g" "$SECRETS_FILE"
        sed -i "s/REPLACE_WITH_GITHUB_CLIENT_SECRET/$client_secret/g" "$SECRETS_FILE"
        sed -i "s/REPLACE_WITH_GENERATED_RPC_SECRET/$rpc_secret/g" "$SECRETS_FILE"
        sed -i "s/REPLACE_WITH_SERVER_HOST/$server_host/g" "$SECRETS_FILE"
        
        echo ""
        echo -e "${GREEN}✓ Secrets file updated!${NC}"
    else
        echo ""
        echo "Manual configuration required:"
        echo "1. Edit: $SECRETS_FILE"
        echo "2. Replace all REPLACE_WITH_* values with real credentials"
    fi
else
    echo -e "${GREEN}✓ Secrets file appears to be configured${NC}"
fi

echo ""
echo -e "${BOLD}=== Next Steps ===${NC}"
echo "1. Validate configuration: ./scripts/validate_drone_config.sh"
echo "2. Deploy: ansible-playbook -i inventory.txt ansible/subsites/05-extra_apps.yaml"
echo "3. Check drone pod logs: kubectl logs -n drone -l app=drone"
echo ""
echo "If drone pods are still crashing after deployment, check the troubleshooting guide:"
echo "docs/troubleshooting/crashloop_fixes.md"