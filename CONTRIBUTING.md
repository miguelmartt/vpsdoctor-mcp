# Contributing

Issues and pull requests are welcome.

## Adding a tool

1. Add a new script under `scripts/`, following the existing ones: it should print a single JSON object to stdout on success, and exit non-zero with an error on stderr on failure.
2. Re-run `scripts/install.sh` on a test VPS so the new script is copied and covered by the sudoers rule.
3. Register a matching `@mcp.tool()` in `src/vpsdoctor_mcp/server.py`, with `ToolAnnotations` that accurately describe whether it's read-only / destructive / idempotent.
4. If the tool changes state on the VPS, follow the existing two-step `confirm` pattern.
5. Add or update a test under `tests/`.

## Local development

```bash
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
ruff check .
pytest
shellcheck scripts/*.sh   # if you touched anything under scripts/
```

## Reporting security issues

Please open an issue describing the concern. Don't include real hostnames, IPs, or credentials in reports or test fixtures.
