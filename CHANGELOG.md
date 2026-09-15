# Changelog

All notable changes to this project are documented here.

## [0.1.0] - 2026-09-15

Initial release.

- `vps_status`, `vps_list_banned_ips`, `vps_restart_service`, `vps_unban_ip` MCP tools
- Vetted shell scripts + restricted sudoers user pattern (`scripts/install.sh`)
- Two-step confirmation for destructive actions
- Restart allowlist enforced independently on both the Python and shell side
