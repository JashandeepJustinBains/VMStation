#!/bin/bash
# This installs Jenkins, Ansible, Prometheus, and Grafana for orchestration & monitoring
echo "Installing Master Node tools..."
apt install -y ansible openjdk-11-jdk jenkins prometheus grafana

echo "Enabling services..."
systemctl enable grafana-server
systemctl start grafana-server
systemctl enable jenkins
systemctl start jenkins

echo "Master node setup complete!"
