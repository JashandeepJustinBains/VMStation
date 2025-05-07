#!/bin/bash
# This node will handle logs & assist with computing.
echo "Installing Logging + Worker tools..."
apt install -y rsyslog logrotate dstat sysstat openmpi-bin openmpi-common libopenmpi-dev prometheus-node-exporter

echo "Logger node setup complete!"
