#!/opt/homebrew/bin/bash
# Version: 1.0.0
# ==============================================================================
# setup_pq_ssh.sh — Post-Quantum SSH setup, load, and verify for GitHub
# ==============================================================================
# Usage:
#   setup_pq_ssh.sh               Generate key + configure ~/.ssh/config (dry-run)
#   setup_pq_ssh.sh --apply       Apply changes (generate key if missing, patch config)
#   setup_pq_ssh.sh --load        Load key into ssh-agent (macOS Keychain aware)
#   setup_pq_ssh.sh --verify      Test live GitHub SSH connectivity + KEX algorithm
#   setup_pq_ssh.sh --status      Show key/agent/config/GitHub status summary
#   setup_pq_ssh.sh --help        Show this help
#
# Exit codes:
#   0  All green
#   1  Warnings (key missing, not loaded, connectivity failed)
#   2  Fatal error
#
# Environment:
#   PQ_KEY_PATH    Override key path (default: ~/.ssh/id_ed25519_pq)
#   PQ_KEX_ALGOS   Override KEX algorithm string
# ==============================================================================
set -euo pipefail
IFS=$'\n\t'

# ── Dry-run gate (EPM bash standard C5) ──────────────────────────────────────
APPLY=0

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

ok()     { printf "${GREEN}  ✓${RESET}  %s\n" "$*"; }
warn()   { printf "${YELLOW}  ⚠${RESET}  %s\n" "$*"; }
fail()   { printf "${RED}  ✗${RESET}  %s\n" "$*"; }
info()   { printf "${BLUE}  ·${RESET}  %s\n" "$*"; }
header() { printf "\n${BOLD}${CYAN}%s${RESET}\n" "$*"; }
dry()    { printf "${YELLOW}  [dry-run]${RESET}  %s\n" "$*"; }

# ── Config ────────────────────────────────────────────────────────────────────
SSH_DIR="${HOME}/.ssh"
KEY_PATH="${PQ_KEY_PATH:-${SSH_DIR}/id_ed25519_pq}"
CONFIG_PATH="${SSH_DIR}/config"
KEX_ALGOS="${PQ_KEX_ALGOS:-mlkem768x25519-sha256,sntrup761x25519-sha512,curve25519-sha256}"
KEX_LINE="KexAlgorithms ${KEX_ALGOS}"
MARKER_BEGIN="# BEGIN pq-ssh github.com"
MARKER_END="# END pq-ssh github.com"

# ── Helpers ───────────────────────────────────────────────────────────────────

is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }

key_exists()   { [[ -f "$KEY_PATH" ]]; }
pubkey_exists() { [[ -f "${KEY_PATH}.pub" ]]; }

key_loaded_in_agent() {
    ssh-add -l 2>/dev/null | grep -qF "${KEY_PATH}" || \
    ssh-add -l 2>/dev/null | grep -qF "$(basename "${KEY_PATH}")"
}

config_block_present() {
    [[ -f "$CONFIG_PATH" ]] && grep -qF "$MARKER_BEGIN" "$CONFIG_PATH"
}

github_connectivity() {
    local out
    out="$(ssh -T -o BatchMode=yes -o ConnectTimeout=8 -o IdentityFile="${KEY_PATH}" \
              -o IdentitiesOnly=yes git@github.com 2>&1)" || true
    printf '%s' "$out"
}

github_kex_algo() {
    local out
    out="$(ssh -vvv -T -o BatchMode=yes -o ConnectTimeout=8 \
              -o IdentityFile="${KEY_PATH}" -o IdentitiesOnly=yes \
              git@github.com 2>&1)" || true
    printf '%s' "$out" | grep -oE 'kex: algorithm: [^ ]+' | head -1 | sed 's/kex: algorithm: //' || true
}

# ── Commands ──────────────────────────────────────────────────────────────────

cmd_help() {
    grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,2\}//'
    exit 0
}

cmd_status() {
    header "PQ SSH Status"

    # Key
    if key_exists; then
        local fingerprint
        fingerprint="$(ssh-keygen -lf "${KEY_PATH}" 2>/dev/null | awk '{print $2}' || echo 'unknown')"
        ok "Key:        ${KEY_PATH} (${fingerprint})"
    else
        warn "Key:        missing — run: setup_pq_ssh.sh --apply"
    fi

    # Public key
    if pubkey_exists; then
        ok "Public key: ${KEY_PATH}.pub"
    else
        warn "Public key: missing"
    fi

    # Agent
    if key_loaded_in_agent; then
        ok "Agent:      key loaded"
    else
        warn "Agent:      key NOT loaded — run: setup_pq_ssh.sh --load"
    fi

    # Config
    if config_block_present; then
        ok "Config:     PQ KEX block present in ${CONFIG_PATH}"
    else
        warn "Config:     PQ KEX block missing — run: setup_pq_ssh.sh --apply"
    fi

    # GitHub connectivity
    info "Checking GitHub connectivity..."
    local out
    out="$(github_connectivity)"
    if printf '%s' "$out" | grep -qi "^Hi "; then
        local gh_user
        gh_user="$(printf '%s' "$out" | grep -oE 'Hi [^!]+' | sed 's/^Hi //')"
        ok "GitHub:     authenticated as ${gh_user}"
    elif printf '%s' "$out" | grep -qi "Permission denied\|publickey"; then
        warn "GitHub:     permission denied — key not uploaded? Run: gh ssh-key add ${KEY_PATH}.pub"
    else
        warn "GitHub:     inconclusive — ${out}"
    fi

    printf '\n'
}

cmd_apply() {
    header "PQ SSH Setup"

    # Create ~/.ssh
    if [[ ! -d "$SSH_DIR" ]]; then
        info "Creating ${SSH_DIR}"
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
    fi

    # Generate key
    if key_exists; then
        ok "Key already exists: ${KEY_PATH}"
    else
        info "Generating Ed25519 key: ${KEY_PATH}"
        ssh-keygen -t ed25519 -a 64 -f "$KEY_PATH" -C "pq-kex-$(hostname -s)"
        ok "Key generated: ${KEY_PATH}"
        printf '\n'
        warn "Upload public key to GitHub:"
        info "  gh ssh-key add ${KEY_PATH}.pub --title pq-$(hostname -s)"
        info "  or: https://github.com/settings/ssh/new"
        printf '\n'
    fi

    # Ensure config file exists
    touch "$CONFIG_PATH"
    chmod 600 "$CONFIG_PATH"

    # Write config block (idempotent — remove old block first if present)
    if config_block_present; then
        ok "Config: PQ KEX block already present"
    else
        info "Appending PQ KEX block to ${CONFIG_PATH}"
        {
            printf '\n%s\n' "$MARKER_BEGIN"
            printf 'Host github.com\n'
            printf '  %s\n' "$KEX_LINE"
            printf '  IdentityFile %s\n' "$KEY_PATH"
            printf '  IdentitiesOnly yes\n'
            printf '%s\n' "$MARKER_END"
        } >> "$CONFIG_PATH"
        ok "Config: PQ KEX block written"
    fi

    printf '\n'
    ok "Setup complete. Next steps:"
    info "  1. Load key:    setup_pq_ssh.sh --load"
    info "  2. Verify:      setup_pq_ssh.sh --verify"
}

cmd_load() {
    header "Loading key into ssh-agent"

    if ! key_exists; then
        fail "Key not found: ${KEY_PATH} — run --apply first"
        exit 1
    fi

    if key_loaded_in_agent; then
        ok "Key already loaded in agent"
        exit 0
    fi

    if is_macos; then
        # macOS Keychain: passphrase stored after first entry, never asked again
        info "Adding key with macOS Keychain support (--apple-use-keychain)"
        ssh-add --apple-use-keychain "$KEY_PATH"
    else
        ssh-add "$KEY_PATH"
    fi

    if key_loaded_in_agent; then
        ok "Key loaded: ${KEY_PATH}"
    else
        fail "ssh-add succeeded but key not visible in agent"
        exit 2
    fi
    printf '\n'
}

cmd_verify() {
    header "Verifying GitHub SSH connectivity"

    if ! key_exists; then
        fail "Key not found: ${KEY_PATH}"
        exit 1
    fi

    if ! key_loaded_in_agent; then
        warn "Key not in agent — attempting to load..."
        cmd_load
    fi

    info "Testing SSH handshake (BatchMode)..."
    local out
    out="$(github_connectivity)"

    if printf '%s' "$out" | grep -qi "^Hi "; then
        local gh_user
        gh_user="$(printf '%s' "$out" | grep -oE 'Hi [^!]+' | sed 's/^Hi //')"
        ok "Authenticated as: ${gh_user}"
    elif printf '%s' "$out" | grep -qi "Permission denied\|publickey"; then
        fail "Permission denied — has the public key been uploaded to GitHub?"
        info "  gh ssh-key add ${KEY_PATH}.pub --title pq-$(hostname -s)"
        exit 1
    else
        fail "Unexpected response: ${out}"
        exit 1
    fi

    info "Checking negotiated KEX algorithm (this takes ~3s)..."
    local algo
    algo="$(github_kex_algo)"
    if [[ -z "$algo" ]]; then
        warn "Could not detect KEX algorithm (verbose output parsing failed)"
    elif printf '%s' "$algo" | grep -qE "mlkem|sntrup"; then
        ok "KEX algorithm: ${algo} ✨ post-quantum active"
    elif [[ "$algo" == "curve25519-sha256" ]]; then
        warn "KEX algorithm: ${algo} (classical fallback — remote does not support PQ KEX)"
    else
        info "KEX algorithm: ${algo}"
    fi
    printf '\n'
}

# ── Argument parsing ──────────────────────────────────────────────────────────

MODE="default"
for arg in "$@"; do
    case "$arg" in
        --apply)   APPLY=1; MODE="apply" ;;
        --load)    MODE="load" ;;
        --verify)  MODE="verify" ;;
        --status)  MODE="status" ;;
        --help|-h) MODE="help" ;;
        *) fail "Unknown argument: ${arg}"; exit 2 ;;
    esac
done

case "$MODE" in
    help)    cmd_help ;;
    status)  cmd_status ;;
    load)    cmd_load ;;
    verify)  cmd_verify ;;
    apply)   cmd_apply ;;
    default)
        printf "${BOLD}PQ SSH setup${RESET} — dry-run mode (no changes made)\n\n"
        cmd_status
        printf "${YELLOW}Run with --apply to make changes, --load to unlock, --verify to test.${RESET}\n\n"
        ;;
esac

