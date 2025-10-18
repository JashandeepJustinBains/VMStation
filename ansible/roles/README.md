# Roles

Reusable Ansible roles for VMStation.

- `preflight-rhel10/`: RHEL 10 preflight checks and system preparation (see role README)

Add new roles here following Ansible Galaxy layout.

## Role-level nonstandard behaviors

- `preflight-rhel10`
	- Includes extended systemd checks and alternative package paths to handle RHEL image variants where `containerd` or other runtime packages are provided by modules or vendor repositories.
	- Runs additional diagnostics and creates an artifact in `ansible/artifacts/` on failures to simplify remote debugging.

When adding roles, follow the existing pattern of idempotency and clear diagnostics output.
