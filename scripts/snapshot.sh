#!/usr/bin/env bash
# Prints a single JSON object describing the VPS: service states, disk,
# RAM, uptime, TLS certificate expiry, fail2ban summary, and (optionally)
# the age of the last backup. No arguments.
#
# Installed at $SCRIPTS_DIR/snapshot.sh on the VPS and invoked as:
#   sudo -n $SCRIPTS_DIR/snapshot.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_FILE="$SCRIPT_DIR/allowed_services.conf"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/config.sh" ]] && source "$SCRIPT_DIR/config.sh"

json_escape() {
    # Minimal JSON string escaping without extra dependencies.
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    printf '%s' "$s"
}

# --- services ---------------------------------------------------------
services_json="{"
first=1
if [[ -f "$SERVICES_FILE" ]]; then
    while IFS= read -r svc; do
        [[ -z "$svc" || "$svc" == \#* ]] && continue
        state=$(systemctl is-active "$svc" 2>/dev/null || true)
        [[ $first -eq 0 ]] && services_json+=","
        services_json+="\"$(json_escape "$svc")\":\"$(json_escape "$state")\""
        first=0
    done < "$SERVICES_FILE"
fi
services_json+="}"

# --- disk / ram / uptime ----------------------------------------------
disk_pct=$(df -h / --output=pcent | tail -1 | tr -d ' %')
ram_line=$(free -m | awk '/^Mem:/ {printf "%d/%d", $3, $2}')
uptime_pretty=$(uptime -p 2>/dev/null || uptime)

# --- TLS certificates (best-effort; skips cleanly if certbot absent) ---
certs_json="[]"
if command -v certbot >/dev/null 2>&1; then
    cert_entries=()
    cert_name=""
    while IFS= read -r line; do
        if [[ "$line" =~ Certificate\ Name:\ (.*) ]]; then
            cert_name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ Expiry\ Date:\ (.*) ]]; then
            cert_entries+=("{\"name\":\"$(json_escape "$cert_name")\",\"expiry\":\"$(json_escape "${BASH_REMATCH[1]}")\"}")
        fi
    done < <(certbot certificates 2>/dev/null || true)
    if [[ ${#cert_entries[@]} -gt 0 ]]; then
        certs_json="[$(IFS=,; echo "${cert_entries[*]}")]"
    fi
fi

# --- fail2ban summary ----------------------------------------------------
f2b_json="{}"
if command -v fail2ban-client >/dev/null 2>&1; then
    jails=$(fail2ban-client status 2>/dev/null | awk -F: '/Jail list/ {print $2}' | tr -d ' ' | tr ',' ' ')
    f2b_json="{"
    jfirst=1
    for jail in $jails; do
        banned=$(fail2ban-client status "$jail" 2>/dev/null | awk -F: '/Currently banned/ {gsub(/ /,"",$2); print $2}')
        [[ $jfirst -eq 0 ]] && f2b_json+=","
        f2b_json+="\"$(json_escape "$jail")\":${banned:-0}"
        jfirst=0
    done
    f2b_json+="}"
fi

# --- last backup age (optional) ---------------------------------------
backup_json="null"
if [[ -n "${BACKUP_MARKER_PATH:-}" && -e "${BACKUP_MARKER_PATH:-}" ]]; then
    last_epoch=$(stat -c %Y "$BACKUP_MARKER_PATH")
    now_epoch=$(date +%s)
    age_hours=$(( (now_epoch - last_epoch) / 3600 ))
    backup_json="{\"marker\":\"$(json_escape "$BACKUP_MARKER_PATH")\",\"age_hours\":$age_hours}"
fi

cat <<EOF
{
  "services": $services_json,
  "disk_used_pct": $disk_pct,
  "ram_used_mb_of_total": "$ram_line",
  "uptime": "$(json_escape "$uptime_pretty")",
  "tls_certificates": $certs_json,
  "fail2ban_banned_by_jail": $f2b_json,
  "last_backup": $backup_json
}
EOF
