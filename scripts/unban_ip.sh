#!/usr/bin/env bash
# Unban an IP address from a fail2ban jail.
# Usage: unban_ip.sh <ip> [jail]   (jail defaults to sshd)
set -euo pipefail

ip="${1:-}"
jail="${2:-sshd}"

if [[ -z "$ip" ]]; then
    echo '{"ok":false,"error":"missing ip argument"}' >&2
    exit 1
fi

# Basic IPv4/IPv6 sanity check. The MCP server already validates this with
# Python's ipaddress module before it gets here — this is the redundant
# second check on the VPS side.
if [[ ! "$ip" =~ ^[0-9a-fA-F:.]+$ ]]; then
    echo '{"ok":false,"error":"invalid ip address"}' >&2
    exit 1
fi

if [[ ! "$jail" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo '{"ok":false,"error":"invalid jail name"}' >&2
    exit 1
fi

output=$(fail2ban-client set "$jail" unbanip "$ip" 2>&1) && ok=true || ok=false

if [[ "$ok" == "true" ]]; then
    printf '{"ok":true,"action":"unban","ip":"%s","jail":"%s"}\n' "$ip" "$jail"
else
    esc_output=${output//\"/\\\"}
    printf '{"ok":false,"action":"unban","ip":"%s","jail":"%s","error":"%s"}\n' "$ip" "$jail" "$esc_output" >&2
    exit 1
fi
