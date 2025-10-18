# Scripts

Helper scripts for deployment, validation, and Kubespray integration.

## Scripts

- `run-kubespray.sh`: Wrapper to stage and run Kubespray
- `activate-kubespray-env.sh`: Activate Python/Ansible environment for Kubespray
- `ops-kubespray-automation.sh`: Opinionated automation for common ops tasks

## Usage

These scripts are designed for Linux shells; on Windows, use WSL. Ensure executable bit is set and run from repo root.

Examples:

```bash
./scripts/run-kubespray.sh
```

## Best Practices

- Do not hardcode credentials; rely on inventory/group vars
- Validate cluster health after operations using tests in `../tests`
