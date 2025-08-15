# Ansible Setup: MiniPC Monitoring Node

This guide describes how to use Ansible to set up Prometheus, Grafana, and Loki on your MiniPC.

## Inventory Example
```ini
[monitoring]
minipc ansible_host=192.168.1.X ansible_user=youruser
```

## Playbook Example
```yaml
- hosts: monitoring
  become: true
  tasks:
    - name: Install dependencies
      apt:
        name:
          - docker.io
          - docker-compose
        state: present
    - name: Copy docker-compose file
      copy:
        src: files/monitoring-compose.yaml
        dest: /home/youruser/monitoring-compose.yaml
    - name: Start monitoring stack
      command: docker-compose -f /home/youruser/monitoring-compose.yaml up -d
```

## docker-compose Example (files/monitoring-compose.yaml)
```yaml
version: '3'
services:
  prometheus:
    image: prom/prometheus
    ports:
      - "9090:9090"
  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
  loki:
    image: grafana/loki
    ports:
      - "3100:3100"
```

## Tips
- Secure Grafana with a password
- Set up Prometheus scrape configs for all nodes
- Use Ansible Vault for secrets
