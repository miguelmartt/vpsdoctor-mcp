"""Configuration loading for vertiguard-mcp.

Everything the server needs comes from environment variables (loaded from a
.env file if present). Nothing sensitive ever lives in code, so this module
is safe to keep in a public repository.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field

from dotenv import load_dotenv

load_dotenv()


class ConfigError(RuntimeError):
    """Raised when required configuration is missing or invalid."""


def _split_csv(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


@dataclass(frozen=True)
class Settings:
    # SSH connection to the target VPS.
    vps_host: str
    vps_port: int
    vps_user: str
    vps_ssh_key_path: str

    # Where the vetted shell scripts (see scripts/) are installed on the VPS.
    scripts_dir: str

    # Services this server is allowed to restart. Keep this list narrow —
    # it is enforced both here and (independently) inside restart_service.sh.
    allowed_services: list[str] = field(default_factory=list)

    # Optional: a path on the VPS whose mtime is checked as a "last backup
    # ran" signal. Leave unset to skip that part of the status report.
    backup_marker_path: str | None = None

    ssh_connect_timeout: int = 10
    command_timeout: int = 20

    @classmethod
    def from_env(cls) -> Settings:
        host = os.getenv("VPS_HOST")
        user = os.getenv("VPS_USER")
        key_path = os.getenv("VPS_SSH_KEY_PATH")

        missing = [
            name
            for name, value in (
                ("VPS_HOST", host),
                ("VPS_USER", user),
                ("VPS_SSH_KEY_PATH", key_path),
            )
            if not value
        ]
        if missing:
            raise ConfigError(
                "Missing required environment variables: "
                + ", ".join(missing)
                + ". Copy .env.example to .env and fill it in."
            )

        return cls(
            vps_host=host,  # type: ignore[arg-type]
            vps_port=int(os.getenv("VPS_PORT", "22")),
            vps_user=user,  # type: ignore[arg-type]
            vps_ssh_key_path=os.path.expanduser(key_path),  # type: ignore[arg-type]
            scripts_dir=os.getenv("SCRIPTS_DIR", "/opt/vertiguard-mcp"),
            allowed_services=_split_csv(os.getenv("ALLOWED_SERVICES", "nginx")),
            backup_marker_path=os.getenv("BACKUP_MARKER_PATH") or None,
            ssh_connect_timeout=int(os.getenv("SSH_CONNECT_TIMEOUT", "10")),
            command_timeout=int(os.getenv("COMMAND_TIMEOUT", "20")),
        )
