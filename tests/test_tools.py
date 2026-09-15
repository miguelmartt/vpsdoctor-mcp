"""Tests for the guard logic in server.py that doesn't require a live VPS:
whitelist enforcement, the two-step confirm gate, and IP validation.
"""

from vertiguard_mcp.server import vps_restart_service, vps_unban_ip


def _set_env(monkeypatch):
    monkeypatch.setenv("VPS_HOST", "vps.example.com")
    monkeypatch.setenv("VPS_USER", "vertiguard-mcp")
    monkeypatch.setenv("VPS_SSH_KEY_PATH", "~/.ssh/id_ed25519")
    monkeypatch.setenv("ALLOWED_SERVICES", "nginx,mariadb")


def test_restart_refuses_service_outside_allowlist(monkeypatch):
    _set_env(monkeypatch)
    result = vps_restart_service("postgresql")
    assert "error" in result
    assert "not in ALLOWED_SERVICES" in result["error"]


def test_restart_requires_confirmation(monkeypatch):
    _set_env(monkeypatch)
    result = vps_restart_service("nginx")
    assert result["confirm_required"] is True
    assert result["would_restart"] == "nginx"


def test_unban_rejects_invalid_ip(monkeypatch):
    _set_env(monkeypatch)
    result = vps_unban_ip("not-an-ip")
    assert "error" in result


def test_unban_requires_confirmation_for_valid_ip(monkeypatch):
    _set_env(monkeypatch)
    result = vps_unban_ip("203.0.113.7")
    assert result["confirm_required"] is True
    assert result["would_unban"] == "203.0.113.7"
