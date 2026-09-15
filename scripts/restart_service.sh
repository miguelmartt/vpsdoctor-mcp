#!/usr/bin/env bash
# Restart a single systemd service, but only if it's on the allowlist.
# Usage: restart_service.sh <service-name>
#
# This is the second line of defense: the Python server already checks
# ALLOWED_SERVICES before it ever SSHes in, but this script re-checks
# independently against allowed_services.conf so a bug or a stale config
# on the Python side can't cause something outside the list to restart.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_FILE="$SCRIPT_DIR/allowed_services.conf"

service="${1:-}"

if [[ -z "$service" ]]; then
    echo '{"ok":false,"error":"missing service argument"}' >&2
    exit 1
fi

# systemd unit names: keep this strict.
if [[ ! "$service" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    echo '{"ok":false,"error":"invalid service name"}' >&2
    exit 1
fi

if ! grep -qxF "$service" "$SERVICES_FILE" 2>/dev/null; then
    printf '{"ok":false,"error":"%s is not in allowed_services.conf"}\n' "$service" >&2
    exit 1
fi

if systemctl restart "$service"; then
    state=$(systemctl is-active "$service" 2>/dev/null || true)
    printf '{"ok":true,"action":"restart","service":"%s","state":"%s"}\n' "$service" "$state"
else
    printf '{"ok":false,"action":"restart","service":"%s","error":"systemctl restart failed"}\n' "$service" >&2
    exit 1
fi
