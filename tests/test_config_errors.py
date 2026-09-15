"""Regression tests for the review pass: missing config and connection
failures must come back as clean tool-error dicts, never raw exceptions.
"""

import paramiko
import pytest

from vpsdoctor_mcp.config import Settings
from vpsdoctor_mcp.server import vps_status
from vpsdoctor_mcp.ssh_client import RemoteCommandError, VpsSSH


def test_vps_status_reports_missing_config_instead_of_raising(monkeypatch):
    monkeypatch.delenv("VPS_HOST", raising=False)
    monkeypatch.delenv("VPS_USER", raising=False)
    monkeypatch.delenv("VPS_SSH_KEY_PATH", raising=False)

    result = vps_status()  # must not raise

    assert "error" in result


def test_connection_failure_is_wrapped(monkeypatch):
    settings = Settings(
        vps_host="vps.example.com",
        vps_port=22,
        vps_user="vpsdoctor-mcp",
        vps_ssh_key_path="/dev/null",
        scripts_dir="/opt/vpsdoctor-mcp",
        allowed_services=["nginx"],
    )

    def boom(self, *args, **kwargs):
        raise paramiko.SSHException("nope")

    monkeypatch.setattr(paramiko.SSHClient, "connect", boom)

    ssh = VpsSSH(settings)
    with pytest.raises(RemoteCommandError):
        ssh.run_script("snapshot.sh")


def test_auth_failure_gives_a_specific_message(monkeypatch):
    settings = Settings(
        vps_host="vps.example.com",
        vps_port=22,
        vps_user="vpsdoctor-mcp",
        vps_ssh_key_path="/dev/null",
        scripts_dir="/opt/vpsdoctor-mcp",
        allowed_services=["nginx"],
    )

    def boom(self, *args, **kwargs):
        raise paramiko.AuthenticationException("denied")

    monkeypatch.setattr(paramiko.SSHClient, "connect", boom)

    ssh = VpsSSH(settings)
    with pytest.raises(RemoteCommandError, match="authentication"):
        ssh.run_script("snapshot.sh")
