Idle-sleep role
===============

Installs a simple hourly check on the masternode that writes a small Prometheus textfile metric
used by node_exporter's textfile collector and optionally sends WOL packets to worker nodes when the
cluster is idle (no active Jellyfin connections).

Configuration:
- Set `vmstation_wol_macs` in your encrypted `group_vars` (vault) to a list of MAC addresses.
