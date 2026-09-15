import pytest

from vpsdoctor_mcp.config import ConfigError, Settings


def test_from_env_requires_host_user_key(monkeypatch):
    monkeypatch.delenv("VPS_HOST", raising=False)
    monkeypatch.delenv("VPS_USER", raising=False)
    monkeypatch.delenv("VPS_SSH_KEY_PATH", raising=False)
    with pytest.raises(ConfigError):
        Settings.from_env()


def test_from_env_reads_values(monkeypatch):
    monkeypatch.setenv("VPS_HOST", "vps.example.com")
    monkeypatch.setenv("VPS_USER", "vpsdoctor-mcp")
    monkeypatch.setenv("VPS_SSH_KEY_PATH", "~/.ssh/id_ed25519")
    monkeypatch.setenv("ALLOWED_SERVICES", "nginx, mariadb ,docker")

    settings = Settings.from_env()

    assert settings.vps_host == "vps.example.com"
    assert settings.vps_port == 22
    assert settings.allowed_services == ["nginx", "mariadb", "docker"]
    assert settings.scripts_dir == "/opt/vpsdoctor-mcp"
