"""vertiguard-mcp server: exposes VPS status and control as MCP tools.

Design notes
------------
* Every write action (restart, unban) requires an explicit ``confirm=True``
  on top of whatever confirmation your MCP client already does. The first
  call without it returns a description of what would happen and does
  nothing — this is the same human-in-the-loop pattern used across
  VerticeDev's other agents (see biwenger-agent): the model is expected to
  relay that back to the person and only call again once they say yes.
* Tools are annotated (readOnlyHint / destructiveHint / idempotentHint) so
  MCP clients that use annotations to decide when to prompt the user do the
  right thing automatically, independent of the confirm= safeguard above.
* All actual system access happens through the vetted scripts in scripts/,
  run as a restricted user via sudo -n (see ssh_client.py and
  scripts/install.sh). This server cannot run arbitrary shell commands.
"""

from __future__ import annotations

import ipaddress
import logging

from mcp.server.fastmcp import FastMCP
from mcp.types import ToolAnnotations

from .config import ConfigError, Settings
from .ssh_client import RemoteCommandError, VpsSSH

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("vertiguard-mcp")

mcp = FastMCP(
    name="vertiguard-mcp",
    instructions=(
        "Tools to check the status of, and carry out maintenance on, a "
        "self-hosted Linux VPS. Status tools are safe to call freely. "
        "Restart and unban tools change live state: call once to see what "
        "would happen, confirm with the person you're helping, then call "
        "again with confirm=true."
    ),
)

_settings: Settings | None = None
_ssh: VpsSSH | None = None


def _get_ssh() -> VpsSSH:
    global _settings, _ssh
    if _ssh is None:
        _settings = Settings.from_env()
        _ssh = VpsSSH(_settings)
    return _ssh


@mcp.tool(
    annotations=ToolAnnotations(
        title="VPS status",
        readOnlyHint=True,
        idempotentHint=True,
        openWorldHint=False,
    )
)
def vps_status() -> dict:
    """Get a snapshot of the VPS: service states, disk, RAM, uptime, TLS
    certificate expiry, fail2ban summary, and (if configured) the age of
    the last backup. Safe to call any time — read-only.
    """
    ssh = _get_ssh()
    try:
        return ssh.run_script_json("snapshot.sh")
    except RemoteCommandError as exc:
        return {"error": str(exc), "stderr": exc.stderr}


@mcp.tool(
    annotations=ToolAnnotations(
        title="List fail2ban-banned IPs",
        readOnlyHint=True,
        idempotentHint=True,
        openWorldHint=False,
    )
)
def vps_list_banned_ips(jail: str = "sshd") -> dict:
    """List IP addresses currently banned by fail2ban in the given jail
    (default: sshd). Read-only.
    """
    ssh = _get_ssh()
    try:
        return ssh.run_script_json("list_banned_ips.sh", jail)
    except RemoteCommandError as exc:
        return {"error": str(exc), "stderr": exc.stderr}


@mcp.tool(
    annotations=ToolAnnotations(
        title="Restart a service",
        readOnlyHint=False,
        destructiveHint=True,
        idempotentHint=True,
        openWorldHint=False,
    )
)
def vps_restart_service(service: str, confirm: bool = False) -> dict:
    """Restart a system service on the VPS (e.g. nginx, mariadb).

    Only services listed in the server's ALLOWED_SERVICES configuration can
    be restarted — anything else is refused before it ever reaches the VPS.

    This causes a brief service interruption. Call once with confirm=false
    (or omitted) to see what would happen; nothing runs until you call
    again with confirm=true.
    """
    settings = Settings.from_env()
    if service not in settings.allowed_services:
        return {
            "error": (
                f"'{service}' is not in ALLOWED_SERVICES "
                f"({', '.join(settings.allowed_services)}). Refused."
            )
        }

    if not confirm:
        return {
            "would_restart": service,
            "confirm_required": True,
            "message": (
                f"This will restart '{service}' on {settings.vps_host}, "
                "causing a brief interruption. Ask the person you're "
                "helping to confirm, then call vps_restart_service again "
                "with confirm=true."
            ),
        }

    ssh = _get_ssh()
    try:
        return ssh.run_script_json("restart_service.sh", service)
    except RemoteCommandError as exc:
        return {"error": str(exc), "stderr": exc.stderr}


@mcp.tool(
    annotations=ToolAnnotations(
        title="Unban an IP address",
        readOnlyHint=False,
        destructiveHint=False,
        idempotentHint=True,
        openWorldHint=False,
    )
)
def vps_unban_ip(ip: str, jail: str = "sshd", confirm: bool = False) -> dict:
    """Remove an IP address from a fail2ban jail (default: sshd).

    Call once with confirm=false (or omitted) to validate the IP and see
    what would happen; nothing runs until you call again with confirm=true.
    """
    try:
        ipaddress.ip_address(ip)
    except ValueError:
        return {"error": f"'{ip}' is not a valid IP address. Refused."}

    if not confirm:
        return {
            "would_unban": ip,
            "jail": jail,
            "confirm_required": True,
            "message": (
                f"This will unban {ip} from the '{jail}' jail. Ask the "
                "person you're helping to confirm, then call "
                "vps_unban_ip again with confirm=true."
            ),
        }

    ssh = _get_ssh()
    try:
        return ssh.run_script_json("unban_ip.sh", ip, jail)
    except RemoteCommandError as exc:
        return {"error": str(exc), "stderr": exc.stderr}


def main() -> None:
    try:
        Settings.from_env()
    except ConfigError as exc:
        raise SystemExit(f"vertiguard-mcp: {exc}")
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
