#!/usr/bin/env bash
# Sets up the VPS side of vertiguard-mcp:
#   1. A dedicated, unprivileged system user (default: vertiguard-mcp)
#   2. This scripts/ directory copied to /opt/vertiguard-mcp (or $SCRIPTS_DIR)
#   3. A sudoers rule letting that user run ONLY the scripts in that
#      directory, with no password — nothing else
#   4. A dedicated SSH key for that user, so it's never mixed with your
#      own login key
#
# Run this ON THE VPS, as root or via sudo:
#   sudo ./install.sh
#
# It is safe to re-run: it will update the copied scripts and the sudoers
# rule without touching the SSH key if one already exists.
set -euo pipefail

SCRIPTS_DIR="${SCRIPTS_DIR:-/opt/vertiguard-mcp}"
SVC_USER="${SVC_USER:-vertiguard-mcp}"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Run this as root (sudo ./install.sh)." >&2
    exit 1
fi

echo "==> Creating system user '$SVC_USER' (if missing)"
if ! id "$SVC_USER" >/dev/null 2>&1; then
    useradd --system --create-home --shell /usr/sbin/nologin "$SVC_USER"
fi

echo "==> Installing scripts to $SCRIPTS_DIR"
mkdir -p "$SCRIPTS_DIR"
cp "$SOURCE_DIR"/*.sh "$SCRIPTS_DIR"/
cp "$SOURCE_DIR"/allowed_services.conf "$SCRIPTS_DIR"/
[[ -f "$SOURCE_DIR/config.sh" ]] && cp "$SOURCE_DIR/config.sh" "$SCRIPTS_DIR"/
chmod 755 "$SCRIPTS_DIR"/*.sh
chown -R root:root "$SCRIPTS_DIR"

echo "==> Writing sudoers rule (/etc/sudoers.d/vertiguard-mcp)"
cat > /etc/sudoers.d/vertiguard-mcp <<EOF
# Managed by vertiguard-mcp/scripts/install.sh — do not edit by hand.
# $SVC_USER may run ONLY the scripts under $SCRIPTS_DIR, no password.
$SVC_USER ALL=(root) NOPASSWD: $SCRIPTS_DIR/*.sh
EOF
chmod 440 /etc/sudoers.d/vertiguard-mcp
visudo -cf /etc/sudoers.d/vertiguard-mcp

SSH_DIR="/home/$SVC_USER/.ssh"
KEY_PATH="$SSH_DIR/id_ed25519"
mkdir -p "$SSH_DIR"
if [[ ! -f "$KEY_PATH" ]]; then
    echo "==> Generating a dedicated SSH key for $SVC_USER"
    sudo -u "$SVC_USER" ssh-keygen -t ed25519 -N "" -f "$KEY_PATH" -C "$SVC_USER@$(hostname)"
else
    echo "==> SSH key already exists at $KEY_PATH, leaving it alone"
fi
cat "$SSH_DIR/id_ed25519.pub" >> "$SSH_DIR/authorized_keys"
sort -u -o "$SSH_DIR/authorized_keys" "$SSH_DIR/authorized_keys"
chown -R "$SVC_USER:$SVC_USER" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/authorized_keys"

cat <<EOF

Done. Next steps:

1. Copy the PRIVATE key below to wherever vertiguard-mcp runs (your laptop,
   the machine running your MCP client), then delete it from the VPS:
     $KEY_PATH

2. Fill in .env (see .env.example) on the machine running the server:
     VPS_HOST=<this VPS's address>
     VPS_USER=$SVC_USER
     VPS_SSH_KEY_PATH=<path to the private key you just copied>
     SCRIPTS_DIR=$SCRIPTS_DIR
     ALLOWED_SERVICES=<comma-separated systemd service names>

3. Edit $SCRIPTS_DIR/allowed_services.conf on the VPS to match the
   services you actually want restartable.

4. Optional: copy config.sh.example to $SCRIPTS_DIR/config.sh to enable
   the backup-age check in the status snapshot.
EOF
