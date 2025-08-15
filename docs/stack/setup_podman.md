# Podman Setup Guide

## Install Podman
```bash
sudo apt update && sudo apt install podman -y
```

## Example Usage
```bash
podman run -d --name myapp myimage:latest
podman pod create --name mypod
```

## Tips
- Use rootless mode for security
- Integrate with systemd for auto-start
