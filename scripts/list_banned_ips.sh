#!/usr/bin/env bash
# List IPs currently banned in a fail2ban jail.
# Usage: list_banned_ips.sh [jail]   (jail defaults to sshd)
set -euo pipefail

jail="${1:-sshd}"

if [[ ! "$jail" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo '{"ok":false,"error":"invalid jail name"}' >&2
    exit 1
fi

status=$(fail2ban-client status "$jail" 2>&1) || {
    esc=${status//\"/\\\"}
    printf '{"ok":false,"jail":"%s","error":"%s"}\n' "$jail" "$esc" >&2
    exit 1
}

ip_line=$(awk -F: '/IP list/ {print $2}' <<< "$status")
ips=($ip_line)

ips_json="["
first=1
for ip in "${ips[@]}"; do
    [[ $first -eq 0 ]] && ips_json+=","
    ips_json+="\"$ip\""
    first=0
done
ips_json+="]"

printf '{"ok":true,"jail":"%s","banned_ips":%s}\n' "$jail" "$ips_json"
