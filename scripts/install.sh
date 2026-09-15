#!/usr/bin/env bash
# Sets up the VPS side of vertiguard-mcp:
#   1. A dedicated system user (default: vertiguard-mcp), not in any
#      privileged group
#   2. This scripts/ directory copied to /opt/vertiguard-mcp (or $SCRIPTS_DIR)
#   3. A sudoers rule letting that user run ONLY the scripts in that
#      directory, with no password — nothing else
#   4. A dedicated SSH key for that user, restricted in authorized_keys
#      (no pty, no port/agent/X11 forwarding — command execution only)
#
# Run this ON THE VPS, as root or via sudo:
#   sudo ./install.sh
#
# Safe to re-run: it refreshes the copied scripts, the sudoers rule and the
# authorized_keys restrictions without touching an existing SSH key, then
# runs a self-test at the end.
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
    # A real shell is required: sshd runs "<shell> -c <command>" even for
    # non-interactive `exec_command` calls, and a nologin shell refuses to
    # run anything at all — that would silently break every tool call.
    # The user is still unprivileged; access is scoped by the sudoers rule
    # below and by the authorized_keys restrictions, not by the shell.
    useradd --system --create-home --shell /bin/bash "$SVC_USER"
else
    # Fix up accounts created by an older version of this script that set
    # a nologin shell (which would have made the whole setup non-functional).
    usermod --shell /bin/bash "$SVC_USER"
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

# Restrict what this key can do even if it's used outside vertiguard-mcp:
# no interactive shell (no-pty), no use as a network pivot (no port/agent/
# X11 forwarding), no ~/.ssh/rc. It can still run `exec_command`, which is
# all this server needs.
echo "==> Restricting authorized_keys options for $SVC_USER"
key_opts="no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding"
restricted_line="$key_opts $(cat "$SSH_DIR/id_ed25519.pub")"
: > "$SSH_DIR/authorized_keys.new"
echo "$restricted_line" >> "$SSH_DIR/authorized_keys.new"
mv "$SSH_DIR/authorized_keys.new" "$SSH_DIR/authorized_keys"
chown -R "$SVC_USER:$SVC_USER" "$SSH_DIR"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/authorized_keys"

echo "==> Self-test: running snapshot.sh as $SVC_USER via sudo -n"
if sudo -u "$SVC_USER" sudo -n "$SCRIPTS_DIR/snapshot.sh" >/tmp/vertiguard-mcp-selftest.json 2>/tmp/vertiguard-mcp-selftest.err; then
    echo "    OK — sudoers rule and script both work:"
    sed 's/^/    /' /tmp/vertiguard-mcp-selftest.json
else
    echo "    FAILED — the sudoers rule or snapshot.sh has a problem:" >&2
    sed 's/^/    /' /tmp/vertiguard-mcp-selftest.err >&2
    rm -f /tmp/vertiguard-mcp-selftest.json /tmp/vertiguard-mcp-selftest.err
    exit 1
fi
rm -f /tmp/vertiguard-mcp-selftest.json /tmp/vertiguard-mcp-selftest.err

cat <<EOF

Done — self-test passed. Next steps:

1. Copy the PRIVATE key below to wherever vertiguard-mcp runs (your laptop,
   the machine running your MCP client), then delete it from the VPS:
     $KEY_PATH

2. Fill in .env (see .env.example) on the machine running the server:
     VPS_HOST=<this VPS's address>
     VPS_USER=$SVC_USER
     VPS_SSH_KEY_PATH=<path to the private key you just copied>
     SCRIPTS_DIR=$SCRIPTS_DIR
     ALLOWED_SERVICES=<comma-separated systemd service names>

3. On the machine running the server, make sure this VPS's host key is
   already trusted (ssh-keyscan -H <this VPS's address> >> ~/.ssh/known_hosts
   if you haven't connected to it from there before) — the server refuses
   unknown hosts by design instead of trusting on first use.

4. Edit $SCRIPTS_DIR/allowed_services.conf on the VPS to match the
   services you actually want restartable.

5. Optional: copy config.sh.example to $SCRIPTS_DIR/config.sh to enable
   the backup-age check in the status snapshot.
EOF
