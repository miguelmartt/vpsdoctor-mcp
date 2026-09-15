# vertiguard-mcp

[Leer en español](README.es.md)

An [MCP](https://modelcontextprotocol.io) server that lets any MCP-compatible AI client (Claude Desktop, Claude Code, Cursor, and others) check the status of, and carry out safe maintenance on, a self-hosted Linux VPS — over plain SSH, with no proprietary agent installed on the server.

Ask "how's the server doing?" and get back service states, disk and RAM usage, uptime, TLS certificate expiry, and a fail2ban summary. Ask it to restart a service or unban an IP, and it will explain exactly what that means before touching anything.

## Why

Most VPS-monitoring MCP servers either want you to install a heavyweight agent, or hand the model unrestricted shell access. This one does neither:

- **Just SSH.** No agent, no extra service running on the VPS beyond what you already have.
- **A closed set of vetted scripts**, installed once under `/opt/vertiguard-mcp` on the VPS, each one small enough to read in a minute (see [`scripts/`](scripts/)).
- **A dedicated, unprivileged system user** on the VPS that can, via a narrow `sudoers` rule, run *only* those scripts — nothing else, no full root shell.
- **Destructive actions require explicit confirmation.** Restarting a service or unbanning an IP always takes two calls: the first one reports what would happen and does nothing; only a second call with `confirm=true` actually runs it. This mirrors the human-in-the-loop approach used across VerticeDev's other open-source agents.
- **A restart allowlist enforced twice** — once by the Python server, once again by the shell script itself on the VPS — so a bug on either side can't restart something you didn't intend to expose.

## What it exposes

| Tool | Read-only? | What it does |
|---|---|---|
| `vps_status` | yes | Services, disk, RAM, uptime, TLS certificate expiry, fail2ban summary, backup age |
| `vps_list_banned_ips` | yes | IPs currently banned in a fail2ban jail |
| `vps_restart_service` | no | Restart a service from your allowlist (two-step confirm) |
| `vps_unban_ip` | no | Unban an IP from a fail2ban jail (two-step confirm) |

## Setup

### 1. On the VPS

Copy the `scripts/` folder to the VPS and run the installer as root:

```bash
scp -r scripts/ youruser@your-vps:/tmp/vertiguard-mcp-scripts
ssh youruser@your-vps
cd /tmp/vertiguard-mcp-scripts && sudo ./install.sh
```

This creates a dedicated `vertiguard-mcp` system user, installs the scripts under `/opt/vertiguard-mcp`, writes a `sudoers` rule scoping that user to exactly those scripts, and generates a dedicated SSH keypair. It prints the next steps, including where to copy the private key.

Edit `/opt/vertiguard-mcp/allowed_services.conf` on the VPS to list the services you actually want restartable (one per line — it ships with `nginx` and `mariadb` as examples).

### 2. Where the server runs

```bash
git clone https://github.com/miguelmartt/vertiguard-mcp
cd vertiguard-mcp
pip install -e .
cp .env.example .env   # then edit it
```

`.env`:

```
VPS_HOST=your-vps-ip-or-hostname
VPS_PORT=22
VPS_USER=vertiguard-mcp
VPS_SSH_KEY_PATH=~/.ssh/vertiguard-mcp-key
SCRIPTS_DIR=/opt/vertiguard-mcp
ALLOWED_SERVICES=nginx,mariadb
```

### 3. Point your MCP client at it

Claude Desktop / Claude Code (`claude_desktop_config.json` or equivalent — see [`examples/claude_desktop_config.json`](examples/claude_desktop_config.json)):

```json
{
  "mcpServers": {
    "vertiguard": {
      "command": "vertiguard-mcp",
      "env": {
        "VPS_HOST": "your-vps-ip-or-hostname",
        "VPS_USER": "vertiguard-mcp",
        "VPS_SSH_KEY_PATH": "/absolute/path/to/vertiguard-mcp-key",
        "SCRIPTS_DIR": "/opt/vertiguard-mcp",
        "ALLOWED_SERVICES": "nginx,mariadb"
      }
    }
  }
}
```

Any other MCP client that can launch a stdio server works the same way.

## Security notes

- The private key for the dedicated user should never leave the machine running the server. `install.sh` restricts it in `authorized_keys` (no pty, no port/agent/X11 forwarding) and, via `sudoers`, to running only the scripts in this repo — nothing else, even if that key is ever misused.
- The server refuses unknown SSH host keys (no trust-on-first-use). If this is the first time connecting to the VPS from wherever the server runs, pin its host key first: `ssh-keyscan -H your-vps >> ~/.ssh/known_hosts`.
- Review [`scripts/`](scripts/) before installing — they're short and meant to be read, not trusted blindly.
- `vps_restart_service` and `vps_unban_ip` validate their input twice (once in Python, once in the shell script) before touching anything, and every executed restart/unban is logged at WARNING level for an audit trail.
- This project does not collect telemetry and makes no network calls other than the SSH connection you configure.

## Extending it

Add a new script under `scripts/`, add it to the `sudoers` rule by re-running `install.sh`, and register a matching `@mcp.tool()` in `src/vertiguard_mcp/server.py`. Pull requests for additional read-only status checks are especially welcome.

## Part of the VerticeDev open-source line

Sibling project: [`vertice-automations`](https://github.com/miguelmartt/vertice-automations) (reusable n8n workflow templates, including a Telegram-based version of this same VPS-control idea).

## License

MIT — see [LICENSE](LICENSE).
