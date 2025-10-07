clear
git pull
./deploy.sh reset

# Run comprehensive validation
./tests/test-comprehensive.sh

# Deploy with enhancements
./deploy.sh all --with-rke2 --yes

# Setup auto-sleep
./deploy.sh setup

# Access monitoring (no login required)
curl http://192.168.4.63:30300
curl http://192.168.4.63:30090/api/v1/targets

# Run security audit
./tests/test-security-audit.sh