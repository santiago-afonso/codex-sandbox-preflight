---
name: codex-sandbox-preflight
description: Fast diagnostics for common Codex Linux sandbox surprises (network/socket restrictions and writable_roots), using both host checks and nested `codex sandbox` probes.
---

# Codex Sandbox Preflight

Run:

```bash
scripts/codex-sandbox-preflight.sh [--with-network] [--no-sandbox] [--verbose]
```

What it checks:
- `codex` presence/version/login.
- Basic write access (cwd, `/tmp`, common XDG config/cache dirs).
- `socket()` and DNS on the current process.
- Optional nested sandbox probes via `codex sandbox linux --full-auto`.
- Reads `~/.codex/config.toml` (if present) to report whether common directories are included in `sandbox_workspace_write.writable_roots`.

Notes:
- Intended for Linux/WSL environments; some commands (like `getent`) may not exist on macOS.
- `--with-network` runs an extra nested sandbox pass with `sandbox_workspace_write.network_access=true`.
