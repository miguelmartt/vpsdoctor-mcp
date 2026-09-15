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

# Not awk -F: — an IPv6 address contains colons itself, which would shred
# a "Banned IP list: 2001:db8::1 2001:db8::2" line across fields. Strip
# everything up to the label instead, keeping the rest of the line intact.
ip_line=$(sed -n 's/^.*[Bb]anned IP list:[[:space:]]*//p' <<< "$status")
read -ra ips <<< "$ip_line"

ips_json="["
first=1
for ip in "${ips[@]}"; do
    [[ $first -eq 0 ]] && ips_json+=","
    ips_json+="\"$ip\""
    first=0
done
ips_json+="]"

printf '{"ok":true,"jail":"%s","banned_ips":%s}\n' "$jail" "$ips_json"
