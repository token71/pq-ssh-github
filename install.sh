#!/opt/homebrew/bin/bash
# Version: 1.0.0
# EPM installer for pq-ssh — post-quantum hybrid SSH key lifecycle tool
set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
APPLY=0
UNINSTALL=0
INSTALL_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup_pq_ssh.sh"
BIN_DIR="${HOME}/.bin"
BIN_TARGET="${BIN_DIR}/pq-ssh"
EP_SNIPPET_MARKER="# pq-ssh ep-integration"
EP_INTEGRATION_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ep-integration.sh"
RC_OVERRIDE=""

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
_ok()   { printf '\033[0;32m  ok\033[0m  %s\n' "$*"; }
_warn() { printf '\033[0;33m warn\033[0m  %s\n' "$*"; }
_fail() { printf '\033[0;31m fail\033[0m  %s\n' "$*"; }
_info() { printf '\033[0;34m info\033[0m  %s\n' "$*"; }
_dry()  { printf '\033[0;35m  dry\033[0m  %s\n' "$*"; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)     APPLY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --rc)        shift; RC_OVERRIDE="$1" ;;
    --rc=*)      RC_OVERRIDE="${1#--rc=}" ;;
    --help|-h)
      echo "Usage: install.sh [--apply] [--uninstall] [--rc FILE]"
      echo "  --apply      Execute changes (default is dry-run)"
      echo "  --uninstall  Remove pq-ssh from ~/.bin and rc files"
      echo "  --rc FILE    Target a specific rc file (e.g. --rc ~/.bashrc)"
      exit 0
      ;;
    *) _fail "Unknown argument: $1"; exit 1 ;;
  esac
  shift
done

[[ $APPLY -eq 0 ]] && _info "Dry-run mode — pass --apply to execute changes"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
_do() {
  # Execute or dry-run a command
  if [[ $APPLY -eq 1 ]]; then
    "$@"
  else
    _dry "would run: $*"
  fi
}

_rc_files() {
  local files=()
  if [[ -n "$RC_OVERRIDE" ]]; then
    files+=("$RC_OVERRIDE")
  else
    [[ -f "${HOME}/.zshrc" ]]  && files+=("${HOME}/.zshrc")
    [[ -f "${HOME}/.bashrc" ]] && files+=("${HOME}/.bashrc")
  fi
  echo "${files[@]:-}"
}

_snippet_present() {
  local rc="$1"
  grep -qF "$EP_SNIPPET_MARKER" "$rc" 2>/dev/null
}

_source_line() {
  printf '%s\nsource "%s"  %s\n' "$EP_SNIPPET_MARKER" "$EP_INTEGRATION_SRC" "$EP_SNIPPET_MARKER end"
}

# ---------------------------------------------------------------------------
# Uninstall path
# ---------------------------------------------------------------------------
if [[ $UNINSTALL -eq 1 ]]; then
  _info "Uninstalling pq-ssh…"

  # Remove ~/.bin/pq-ssh
  if [[ -e "$BIN_TARGET" || -L "$BIN_TARGET" ]]; then
    _do rm -f "$BIN_TARGET"
    _ok "Removed $BIN_TARGET"
  else
    _warn "$BIN_TARGET not found — nothing to remove"
  fi

  # Remove ep-integration snippet from rc files
  local_rcs=($(_rc_files))
  if [[ ${#local_rcs[@]} -eq 0 ]]; then
    _warn "No rc files found"
  fi
  for rc in "${local_rcs[@]}"; do
    if _snippet_present "$rc"; then
      _do sed -i.bak "/$EP_SNIPPET_MARKER/,/$EP_SNIPPET_MARKER end/d" "$rc"
      _ok "Removed ep-integration snippet from $rc"
    else
      _warn "Snippet not found in $rc — nothing to remove"
    fi
  done

  [[ $APPLY -eq 0 ]] && _info "Re-run with --apply --uninstall to execute"
  exit 0
fi

# ---------------------------------------------------------------------------
# Status report
# ---------------------------------------------------------------------------
_info "=== pq-ssh install status ==="

# Source script exists?
if [[ -f "$INSTALL_SOURCE" ]]; then
  _ok  "Source:      $INSTALL_SOURCE"
else
  _fail "Source not found: $INSTALL_SOURCE"
  exit 1
fi

# ~/.bin directory
if [[ -d "$BIN_DIR" ]]; then
  _ok  "~/.bin dir:  exists"
else
  _warn "~/.bin dir:  missing — will create"
fi

# ~/.bin/pq-ssh wrapper
if [[ -e "$BIN_TARGET" ]]; then
  _ok  "~/.bin/pq-ssh wrapper: installed"
else
  _warn "~/.bin/pq-ssh wrapper: not installed"
fi

# ep-integration snippet in rc files
local_rcs=($(_rc_files))
if [[ ${#local_rcs[@]} -eq 0 ]]; then
  _warn "No ~/.zshrc or ~/.bashrc found — snippet cannot be sourced automatically"
else
  for rc in "${local_rcs[@]}"; do
    if _snippet_present "$rc"; then
      _ok  "ep-integration: sourced in $rc"
    else
      _warn "ep-integration: NOT sourced in $rc"
    fi
  done
fi

_info "=== applying changes ==="

# ---------------------------------------------------------------------------
# Install: ~/.bin directory
# ---------------------------------------------------------------------------
if [[ ! -d "$BIN_DIR" ]]; then
  _do mkdir -p "$BIN_DIR"
  _ok "Created $BIN_DIR"
fi

# ---------------------------------------------------------------------------
# Install: ~/.bin/pq-ssh wrapper
# ---------------------------------------------------------------------------
if [[ ! -e "$BIN_TARGET" ]]; then
  if [[ $APPLY -eq 1 ]]; then
    cat > "$BIN_TARGET" <<WRAPPER
#!/opt/homebrew/bin/bash
exec "${INSTALL_SOURCE}" "\$@"
WRAPPER
    chmod +x "$BIN_TARGET"
    _ok "Created $BIN_TARGET"
  else
    _dry "would create $BIN_TARGET → exec \"${INSTALL_SOURCE}\" \"\$@\""
  fi
else
  _ok "$BIN_TARGET already exists — skipping"
fi

# ---------------------------------------------------------------------------
# Install: lib/ep-integration.sh exists check
# ---------------------------------------------------------------------------
if [[ ! -f "$EP_INTEGRATION_SRC" ]]; then
  _warn "lib/ep-integration.sh not found — rc snippet will reference a missing file"
  _warn "Create $EP_INTEGRATION_SRC before sourcing the snippet"
fi

# ---------------------------------------------------------------------------
# Install: source snippet into rc files
# ---------------------------------------------------------------------------
if [[ ${#local_rcs[@]} -eq 0 ]]; then
  _warn "No rc files to update — manually source lib/ep-integration.sh"
else
  for rc in "${local_rcs[@]}"; do
    if _snippet_present "$rc"; then
      _ok "ep-integration already sourced in $rc — skipping"
    else
      if [[ $APPLY -eq 1 ]]; then
        printf '\n%s\n' "$(_source_line)" >> "$rc"
        _ok "Added ep-integration snippet to $rc"
      else
        _dry "would append ep-integration snippet to $rc"
      fi
    fi
  done
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
if [[ $APPLY -eq 0 ]]; then
  _info "Dry-run complete — re-run with --apply to make changes"
else
  _ok "Installation complete"
  _info "Reload your shell or run: source ${RC_OVERRIDE:-~/.bashrc}"
fi
