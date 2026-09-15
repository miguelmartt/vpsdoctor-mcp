"""Thin SSH wrapper around paramiko.

The server never runs arbitrary commands on the VPS. It only ever invokes
one of the vetted scripts under ``scripts_dir`` (see scripts/), as the
dedicated restricted user created by scripts/install.sh, via ``sudo -n``.
The sudoers rule installed by that script restricts that user to exactly
those scripts — nothing else — so even a bug on the Python side can't
reach outside that boundary.
"""

from __future__ import annotations

import json
import shlex
from dataclasses import dataclass

import paramiko

from .config import Settings


class RemoteCommandError(RuntimeError):
    """Raised when a remote script exits non-zero or returns unparseable output."""

    def __init__(self, message: str, stdout: str = "", stderr: str = ""):
        super().__init__(message)
        self.stdout = stdout
        self.stderr = stderr


@dataclass
class CommandResult:
    exit_code: int
    stdout: str
    stderr: str


class VpsSSH:
    """Opens one SSH connection per call. Simple and safe for an MCP server
    that receives calls sporadically (interactive tool use, not a hot loop).
    """

    def __init__(self, settings: Settings):
        self._settings = settings

    def _connect(self) -> paramiko.SSHClient:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.RejectPolicy())
        client.load_system_host_keys()
        client.connect(
            hostname=self._settings.vps_host,
            port=self._settings.vps_port,
            username=self._settings.vps_user,
            key_filename=self._settings.vps_ssh_key_path,
            timeout=self._settings.ssh_connect_timeout,
            allow_agent=False,
            look_for_keys=False,
        )
        return client

    def run_script(self, script_name: str, *args: str) -> CommandResult:
        """Run ``sudo -n <scripts_dir>/<script_name> <args...>`` on the VPS.

        ``script_name`` must be a bare filename (no path separators) — this
        is enforced here as a second line of defense on top of the sudoers
        allowlist on the server side.
        """
        if "/" in script_name or ".." in script_name:
            raise ValueError(f"invalid script name: {script_name!r}")

        remote_path = f"{self._settings.scripts_dir}/{script_name}"
        parts = ["sudo", "-n", remote_path, *args]
        command = " ".join(shlex.quote(p) for p in parts)

        client = self._connect()
        try:
            stdin, stdout, stderr = client.exec_command(
                command, timeout=self._settings.command_timeout
            )
            exit_code = stdout.channel.recv_exit_status()
            out = stdout.read().decode("utf-8", errors="replace")
            err = stderr.read().decode("utf-8", errors="replace")
        finally:
            client.close()

        return CommandResult(exit_code=exit_code, stdout=out, stderr=err)

    def run_script_json(self, script_name: str, *args: str) -> dict:
        """Like ``run_script`` but parses stdout as JSON.

        All scripts in scripts/ are expected to print a single JSON object
        on success, so MCP tools can hand it straight back to the model.
        """
        result = self.run_script(script_name, *args)
        if result.exit_code != 0:
            raise RemoteCommandError(
                f"{script_name} exited with status {result.exit_code}",
                stdout=result.stdout,
                stderr=result.stderr,
            )
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError as exc:
            raise RemoteCommandError(
                f"{script_name} did not return valid JSON: {exc}",
                stdout=result.stdout,
                stderr=result.stderr,
            ) from exc
