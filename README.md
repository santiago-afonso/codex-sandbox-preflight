# codex-sandbox-preflight

Fast diagnostics for common Codex Linux sandbox surprises:
- `socket()` blocked by the sandbox (seccomp)
- DNS failures that are downstream of socket restrictions
- missing `sandbox_workspace_write.writable_roots` entries for common XDG dirs

## Usage

```bash
./scripts/codex-sandbox-preflight.sh [--with-network] [--no-sandbox] [--verbose]
```

## Codex skill

This repo is also a Codex CLI skill; see `SKILL.md`.
