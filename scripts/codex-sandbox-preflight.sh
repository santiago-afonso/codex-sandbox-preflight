#!/usr/bin/env bash
# codex-sandbox-preflight.sh
#
# Interpretation notes (generic, high-signal):
# - “Network enabled but sockets denied” can be real *inside* Codex’s Linux OS sandbox:
#   `socket()` may be seccomp-blocked by default, showing `PermissionError: [Errno 1] Operation not permitted`.
#   Outside the sandbox, sockets can work normally.
# - The root cause is often “Codex sandbox is running with network disabled”, not “the runtime forbids sockets globally”
#   and not necessarily “DNS is broken”.
# - Several downstream symptoms (DNS failures, `git push` host resolution failures, auth flows) can be caused by the
#   `socket()` syscall being blocked inside the sandbox; they don’t imply host DNS is broken.
# - `wbg-auth` initializes file logging on startup and will crash if it cannot open `~/.config/wbg-auth/wbg-auth.log`.
#   In a workspace-write sandbox, that path is blocked unless included in `sandbox_workspace_write.writable_roots`.
# - Host-only preflights (e.g., `uv run python -c "import socket"`, `getent hosts ...`) will not catch sandbox-only
#   restrictions; when possible, probe with nested `codex sandbox linux --full-auto ...`.

set -euo pipefail

WITH_NETWORK=0
RUN_NESTED_SANDBOX=1
VERBOSE=0

usage() {
  cat <<'EOF'
codex-sandbox-preflight.sh

Fast diagnostics for common Codex Linux sandbox surprises (network + writable paths).

Usage:
  codex-sandbox-preflight.sh [--with-network] [--no-sandbox] [--verbose]

Options:
  --with-network  Also run a second sandbox pass with
                  -c sandbox_workspace_write.network_access=true
  --no-sandbox    Skip nested `codex sandbox ...` probes (still checks current process)
  --verbose       Print longer error snippets for failing checks
  -h, --help      Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-network) WITH_NETWORK=1; shift ;;
    --no-sandbox) RUN_NESTED_SANDBOX=0; shift ;;
    -v|--verbose) VERBOSE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

say() { printf '%s\n' "$*"; }

summarize_error() {
  local out="${1:-}"
  [[ -n "$out" ]] || return 0

  # Prefer the most "root cause" looking line to keep output short.
  local picked=""
  picked="$(printf '%s\n' "$out" | grep -E 'PermissionError:|NameResolutionError|Could not resolve host|Operation not permitted|seccomp|landlock|sandbox denied|denied' | tail -n 1 2>/dev/null || true)"
  if [[ -z "$picked" ]]; then
    picked="$(printf '%s\n' "$out" | tail -n 1 2>/dev/null || true)"
  fi

  # Collapse whitespace and keep it compact.
  printf '%s' "$picked" | tr '\n' ' ' | sed -e 's/[[:space:]]\\+/ /g' | sed -e 's/[[:space:]]$//'
}

check_cmd() {
  local label="$1"
  shift

  local out rc
  out="$("$@" 2>&1)"
  rc=$?

  if [[ $rc -eq 0 ]]; then
    say "OK  - ${label}"
    return 0
  fi

  say "FAIL- ${label}"
  if [[ -n "$out" ]]; then
    if [[ "$VERBOSE" -eq 1 ]]; then
      say "     $(printf '%s' "$out" | tail -n 8 | tr '\n' ' ' | sed -e 's/[[:space:]]\\+/ /g')"
    else
      say "     $(summarize_error "$out")"
    fi
  fi
  return 1
}

python_socket_check=( )
if command -v python3 >/dev/null 2>&1; then
  python_socket_check=(python3 -c "import socket; s=socket.socket(); s.close()")
elif command -v uv >/dev/null 2>&1; then
  python_socket_check=(uv run python -c "import socket; s=socket.socket(); s.close()")
else
  python_socket_check=(sh -c "echo 'missing python3/uv for socket check' >&2; exit 2")
fi

say "codex-sandbox-preflight"
say
say "Interpretation notes (generic, high-signal)"
say "INFO- In Codex OS sandboxes, socket() can be seccomp-blocked: PermissionError: [Errno 1] Operation not permitted"
say "INFO- Outside the sandbox, socket() can work normally (host network OK != sandbox network OK)"
say "INFO- That usually means sandbox network disabled (not that host DNS is broken); compare host vs: codex sandbox linux --full-auto"
say "INFO- DNS / git / auth failures inside sandbox can be downstream of socket() being blocked"
say "INFO- wbg-auth needs writable ~/.config/wbg-auth in the sandbox (add to sandbox_workspace_write.writable_roots)"
say "INFO- Host-only preflights won't catch sandbox-only restrictions; rely on nested codex sandbox probes"
say

critical_fail=0

check_cmd "codex in PATH" sh -c "command -v codex >/dev/null" || critical_fail=1
check_cmd "codex --version" sh -c "codex --version >/dev/null" || critical_fail=1
check_cmd "codex login status" sh -c "codex login status >/dev/null" || critical_fail=1

say
say "Context"
say "INFO- user=$(id -un 2>/dev/null || echo unknown) uid=$(id -u 2>/dev/null || echo '?') cwd=$(pwd -P 2>/dev/null || pwd)"
if [[ -n "${WSL_DISTRO_NAME:-}" ]] || uname -r 2>/dev/null | grep -qi microsoft; then
  say "INFO- wsl=yes distro=${WSL_DISTRO_NAME:-unknown}"
fi
say "INFO- env HOME=${HOME:-} TMPDIR=${TMPDIR:-<unset>} UV_CACHE_DIR=${UV_CACHE_DIR:-<unset>} XDG_CACHE_HOME=${XDG_CACHE_HOME:-<unset>} XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-<unset>}"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  dirty_count="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  say "INFO- git branch=${branch} dirty_paths=${dirty_count}"
fi

say
say "Tooling"
skills_flag="$(codex features list 2>/dev/null | grep -m1 '^skills' || true)"
if [[ -n "$skills_flag" ]]; then
  say "INFO- codex features: ${skills_flag}"
fi
if command -v uv >/dev/null 2>&1; then
  check_cmd "uv --version" sh -c "uv --version >/dev/null" || true
fi
if command -v python3 >/dev/null 2>&1; then
  check_cmd "python3 -V" sh -c "python3 -V >/dev/null" || true
fi
if command -v git >/dev/null 2>&1; then
  check_cmd "git --version" sh -c "git --version >/dev/null" || true
fi
if command -v bd >/dev/null 2>&1; then
  check_cmd "bd version" sh -c "bd version >/dev/null" || true
fi
if command -v llm >/dev/null 2>&1; then
  check_cmd "llm --version" sh -c "llm --version >/dev/null" || true
fi
if command -v wbg-auth >/dev/null 2>&1; then
  say "OK  - wbg-auth in PATH"
fi

say
say "Current process checks"
check_cmd "write cwd" sh -c 't=".codex_preflight_write.$$"; : >"$t" && rm -f -- "$t"' || true
check_cmd "write /tmp" sh -c 't="/tmp/.codex_preflight_write.$$"; : >"$t" && rm -f -- "$t"' || true

cfg_home="${XDG_CONFIG_HOME:-$HOME/.config}"
cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
uv_cache_dir="${UV_CACHE_DIR:-$cache_home/uv}"

check_cmd "write UV_CACHE_DIR (${uv_cache_dir})" sh -c 'd="${UV_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/uv}"; t="$d/.codex_preflight_write.$$"; mkdir -p "$d" >/dev/null 2>&1 || true; : >"$t" && rm -f -- "$t"' || true
check_cmd "write ${cfg_home}/wbg-auth" sh -c 'd="${XDG_CONFIG_HOME:-$HOME/.config}/wbg-auth"; t="$d/.codex_preflight_write.$$"; mkdir -p "$d" >/dev/null 2>&1 || true; : >"$t" && rm -f -- "$t"' || true
check_cmd "write ${cfg_home}/io.datasette.llm" sh -c 'd="${XDG_CONFIG_HOME:-$HOME/.config}/io.datasette.llm"; t="$d/.codex_preflight_write.$$"; mkdir -p "$d" >/dev/null 2>&1 || true; : >"$t" && rm -f -- "$t"' || true

current_socket_out=""
current_socket_ok=0
if current_socket_out="$("${python_socket_check[@]}" 2>&1)"; then
  say "OK  - socket() syscall"
  current_socket_ok=1
else
  if printf '%s' "$current_socket_out" | grep -q "PermissionError: \\[Errno 1\\] Operation not permitted"; then
    say "INFO- socket() syscall blocked (likely sandbox network disabled)"
  else
    say "WARN- socket() syscall failed: $(summarize_error "$current_socket_out")"
  fi
fi

if [[ "${current_socket_ok}" -eq 1 ]]; then
  check_cmd "dns github.com" sh -c "getent hosts github.com >/dev/null" || true
else
  say "SKIP- dns github.com (socket blocked)"
fi

home_cfg="${HOME}/.codex/config.toml"

say
say "Config linkage"
if [[ -e "$home_cfg" ]]; then
  if [[ -L "$home_cfg" ]]; then
    link_target="$(readlink -f "$home_cfg" 2>/dev/null || true)"
    say "OK  - ~/.codex/config.toml is symlinked to: ${link_target:-<unknown>}"
  else
    say "INFO- ~/.codex/config.toml is a regular file (if you manage it via symlinks, consider re-linking it)"
  fi
else
  say "WARN- ~/.codex/config.toml missing"
fi

say
say "Config sanity (sandbox writable_roots)"
if [[ -r "$home_cfg" ]] && (command -v python3 >/dev/null 2>&1 || command -v uv >/dev/null 2>&1); then
  cfg_report="$(
    if command -v python3 >/dev/null 2>&1; then
      python3 - <<'PY' "$HOME"
import os
import sys
import tomllib

home = sys.argv[1]
cfg_path = os.path.join(home, ".codex", "config.toml")
wanted = [
    os.path.join(home, ".config", "wbg-auth"),
    os.path.join(home, ".cache", "uv"),
    os.path.join(home, "tmp"),
]
try:
    with open(cfg_path, "rb") as handle:
        data = tomllib.load(handle)
except FileNotFoundError:
    print("WARN config.toml missing")
    raise SystemExit(0)
except Exception as exc:
    print(f"WARN failed to parse config.toml: {type(exc).__name__}: {exc}")
    raise SystemExit(0)

sandbox = data.get("sandbox_workspace_write") or {}
network_access = bool(sandbox.get("network_access", False))
roots = sandbox.get("writable_roots") or []
roots_norm = {os.path.normpath(os.path.expanduser(p)) for p in roots if isinstance(p, str)}
model = data.get("model")
approval_presets = data.get("approval_presets")
web_search_request = data.get("web_search_request")
print(
    "INFO "
    + "model="
    + (str(model) if model is not None else "<unset>")
    + " approval_presets="
    + (str(approval_presets) if approval_presets is not None else "<unset>")
    + " web_search_request="
    + (str(web_search_request) if web_search_request is not None else "<unset>")
    + " sandbox_network_access="
    + str(network_access).lower()
)
print(f"INFO writable_roots_count={len(roots_norm)}")
for p in wanted:
    key = os.path.normpath(os.path.expanduser(p))
    if key in roots_norm:
        print(f"OK has_writable_root={key}")
    else:
        print(f"WARN missing_writable_root={key}")
PY
    else
      uv run python - <<'PY' "$HOME"
import os
import sys
import tomllib

home = sys.argv[1]
cfg_path = os.path.join(home, ".codex", "config.toml")
wanted = [
    os.path.join(home, ".config", "wbg-auth"),
    os.path.join(home, ".cache", "uv"),
    os.path.join(home, "tmp"),
]
try:
    with open(cfg_path, "rb") as handle:
        data = tomllib.load(handle)
except FileNotFoundError:
    print("WARN config.toml missing")
    raise SystemExit(0)
except Exception as exc:
    print(f"WARN failed to parse config.toml: {type(exc).__name__}: {exc}")
    raise SystemExit(0)

sandbox = data.get("sandbox_workspace_write") or {}
network_access = bool(sandbox.get("network_access", False))
roots = sandbox.get("writable_roots") or []
roots_norm = {os.path.normpath(os.path.expanduser(p)) for p in roots if isinstance(p, str)}
model = data.get("model")
approval_presets = data.get("approval_presets")
web_search_request = data.get("web_search_request")
print(
    "INFO "
    + "model="
    + (str(model) if model is not None else "<unset>")
    + " approval_presets="
    + (str(approval_presets) if approval_presets is not None else "<unset>")
    + " web_search_request="
    + (str(web_search_request) if web_search_request is not None else "<unset>")
    + " sandbox_network_access="
    + str(network_access).lower()
)
print(f"INFO writable_roots_count={len(roots_norm)}")
for p in wanted:
    key = os.path.normpath(os.path.expanduser(p))
    if key in roots_norm:
        print(f"OK has_writable_root={key}")
    else:
        print(f"WARN missing_writable_root={key}")
PY
    fi
  )"
  printf '%s\n' "$cfg_report"
else
  say "WARN- skipped (need readable ~/.codex/config.toml + python3/uv)"
fi

if [[ "$RUN_NESTED_SANDBOX" -ne 1 ]]; then
  exit "$critical_fail"
fi

# If we're already in a restricted environment (e.g., Codex tool sandbox),
# nested sandbox probes add little value and can be misleading (outer seccomp
# will still block socket()).
if [[ "${current_socket_ok}" -ne 1 ]]; then
  say
  say "Nested sandbox probes"
  say "SKIP- current process blocks socket(); run this script from a normal shell for nested codex sandbox probes"
  exit "$critical_fail"
fi

run_sandbox() {
  codex sandbox linux --full-auto -- "$@"
}

run_sandbox_net() {
  codex sandbox linux --full-auto -c sandbox_workspace_write.network_access=true -- "$@"
}

say
say "Nested sandbox probes (codex sandbox linux --full-auto)"
check_cmd "sandbox write cwd" run_sandbox sh -c 't=".codex_sbx_write_test.$$"; : >"$t" && rm -f -- "$t"' || critical_fail=1
check_cmd "sandbox write /tmp" run_sandbox sh -c 't="/tmp/.codex_sbx_write_test.$$"; : >"$t" && rm -f -- "$t"' || critical_fail=1

sbx_socket_out=""
if sbx_socket_out="$(run_sandbox "${python_socket_check[@]}" 2>&1)"; then
  say "OK  - sandbox socket() syscall"
else
  if printf '%s' "$sbx_socket_out" | grep -q "PermissionError: \\[Errno 1\\] Operation not permitted"; then
    say "INFO- sandbox socket() syscall blocked (expected unless network enabled)"
  else
    say "WARN- sandbox socket() syscall failed: $(summarize_error "$sbx_socket_out")"
  fi
fi

cfg_home="${XDG_CONFIG_HOME:-$HOME/.config}"
check_cmd "sandbox write ${cfg_home}/wbg-auth" run_sandbox sh -c 'd="${XDG_CONFIG_HOME:-$HOME/.config}/wbg-auth"; t="$d/.codex_sbx_write_test.$$"; mkdir -p "$d" >/dev/null 2>&1 || true; : >"$t" && rm -f -- "$t"' || true

if [[ "$WITH_NETWORK" -eq 1 ]]; then
  say
  say "Nested sandbox probes (network enabled)"
  check_cmd "sandbox(net) socket() syscall" run_sandbox_net "${python_socket_check[@]}" || true
  check_cmd "sandbox(net) dns github.com" run_sandbox_net sh -c "getent hosts github.com >/dev/null" || true
  check_cmd "sandbox(net) dns login.microsoftonline.com" run_sandbox_net sh -c "getent hosts login.microsoftonline.com >/dev/null" || true
fi

exit "$critical_fail"
