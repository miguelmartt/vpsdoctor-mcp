# Changelog

All notable changes to this project are documented here.

## [0.1.2] - 2026-09-15

Second review pass, requested explicitly to hunt for bugs and confirm no
credentials had leaked in anywhere.

- **Fix:** `install.sh` hardcoded the dedicated user's home as
  `/home/$SVC_USER`. `useradd`'s actual home-directory placement varies by
  distro; if it ever differed, `sshd` would look for `authorized_keys` in
  the real home while we wrote it to the wrong assumed path, breaking
  auth with no obvious cause. Now derived from `getent passwd`.
- **Fix:** `list_banned_ips.sh` extracted the banned-IP list with
  `awk -F:`, which shreds IPv6 addresses (they contain colons themselves).
  Any jail with an IPv6 ban would have returned a mangled, truncated list.
  Replaced with a label-anchored `sed` extraction.
- Installed and ran `shellcheck` for real (it wasn't available during the
  first pass) — fixed the two findings: an unquoted-word-splitting risk in
  `list_banned_ips.sh` (`read -a` instead of a bare `(...)` expansion) and
  documented one intentional redirect pattern in `install.sh`'s self-test
  with a `shellcheck disable` + explanation, so CI's shellcheck job won't
  flag it or go red on a false positive.
- Verified the IPv6 and IP-list parsing fixes against simulated
  `fail2ban-client` output, and restart/unban against simulated
  `systemctl`/`fail2ban-client`, not just syntax-checked.
- Scanned the full git history (every commit, not just the current tree)
  for credentials, private keys, and Miguel's real VPS IP/chat ID —
  clean. Nothing beyond `.env.example` placeholders was ever committed.

## [0.1.1] - 2026-09-15

Review pass before first publish — two of these were real bugs that would
have kept the server from working at all against a real VPS, not polish.

- **Fix:** `install.sh` created the dedicated user with a `nologin` shell,
  which makes OpenSSH refuse to run `exec_command` at all — every tool call
  would have failed. Now uses a real shell, with access instead restricted
  by `sudoers` and by `authorized_keys` options (no pty, no port/agent/X11
  forwarding).
- **Fix:** the SSH client only checked the system-wide `known_hosts`, not
  the user's own — against a VPS you'd already SSHed into normally, host
  key verification would still fail. Now checks both, and the README
  documents `ssh-keyscan` for a clean first connection.
- **Fix:** connection-level failures (unreachable host, auth failure,
  timeout, unknown host key) weren't caught anywhere and would surface as
  raw exceptions instead of a clean tool error; same for missing `.env`
  configuration on `vps_restart_service` / `vps_unban_ip`. All four tools
  now return a structured `{"error": ...}` in every failure case.
- Removed a module-level settings/connection cache in `server.py` that
  could go stale and disagreed with how `vps_restart_service` re-read
  settings independently — settings are now read fresh each call.
- Added: WARNING-level audit logging for every executed restart/unban.
- Added: `install.sh` now ends with a self-test (runs `snapshot.sh` via
  `sudo -n` as the dedicated user) so a broken sudoers rule or script is
  caught at install time, not on first real use.
- Added: `ruff` lint in CI.

## [0.1.0] - 2026-09-15

Initial release.

- `vps_status`, `vps_list_banned_ips`, `vps_restart_service`, `vps_unban_ip` MCP tools
- Vetted shell scripts + restricted sudoers user pattern (`scripts/install.sh`)
- Two-step confirmation for destructive actions
- Restart allowlist enforced independently on both the Python and shell side
