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

## Sample output

Output varies by machine and whether you run nested sandbox probes, but a typical `--no-sandbox` run looks like:

```text
$ ./scripts/codex-sandbox-preflight.sh --no-sandbox
codex-sandbox-preflight

Interpretation notes (generic, high-signal)
INFO- In Codex OS sandboxes, socket() can be seccomp-blocked: PermissionError: [Errno 1] Operation not permitted
INFO- Outside the sandbox, socket() can work normally (host network OK != sandbox network OK)
INFO- That usually means sandbox network disabled (not that host DNS is broken); compare host vs: codex sandbox linux --full-auto
INFO- DNS / git / auth failures inside sandbox can be downstream of socket() being blocked
INFO- wbg-auth needs writable ~/.config/wbg-auth in the sandbox (add to sandbox_workspace_write.writable_roots)
INFO- Host-only preflights won't catch sandbox-only restrictions; rely on nested codex sandbox probes

OK  - codex in PATH
OK  - codex --version
OK  - codex login status

Context
INFO- user=user uid=1000 cwd=/home/user/tmp/codex-sandbox-preflight
INFO- wsl=yes distro=Ubuntu-24.04
INFO- env HOME=/home/user TMPDIR=<unset> UV_CACHE_DIR=/tmp/uv-cache XDG_CACHE_HOME=<unset> XDG_CONFIG_HOME=<unset>
INFO- git branch=main dirty_paths=0

Tooling
INFO- codex features: skills	experimental	true
OK  - uv --version
OK  - python3 -V
OK  - git --version
OK  - bd version
OK  - llm --version

Current process checks
OK  - write cwd
OK  - write /tmp
OK  - write UV_CACHE_DIR (/tmp/uv-cache)
OK  - write /home/user/.config/wbg-auth
OK  - write /home/user/.config/io.datasette.llm
OK  - socket() syscall
OK  - dns github.com

Config linkage
INFO- ~/.codex/config.toml is a regular file (if you manage it via symlinks, consider re-linking it)

Config sanity (sandbox writable_roots)
INFO model=gpt-5.2 approval_presets=never web_search_request=True sandbox_network_access=false
INFO writable_roots_count=6
OK has_writable_root=/home/user/.config/wbg-auth
OK has_writable_root=/home/user/.cache/uv
OK has_writable_root=/home/user/tmp
```
