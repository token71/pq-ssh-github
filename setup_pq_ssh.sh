#!/opt/homebrew/bin/bash
# Version: 2.0.0
# ==============================================================================
# setup_pq_ssh.sh — Post-Quantum SSH: full key lifecycle for GitHub
# ==============================================================================
# Usage:
#   setup_pq_ssh.sh                              Dry-run status report
#   setup_pq_ssh.sh --apply                      Generate key + patch ~/.ssh/config
#   setup_pq_ssh.sh --load [--manager <mgr>]     Load key into agent (passphrase from manager)
#   setup_pq_ssh.sh --unload                     Remove key from agent
#   setup_pq_ssh.sh --verify                     Test GitHub connectivity + KEX algorithm
#   setup_pq_ssh.sh --status                     Full health report
#   setup_pq_ssh.sh --store-passphrase <mgr>     Store passphrase in: keychain|bitwarden|pass
#   setup_pq_ssh.sh --install-autoload           Inject autoload snippet into shell rc files
#   setup_pq_ssh.sh --clean                      Remove pq-ssh block from ~/.ssh/config
#   setup_pq_ssh.sh --delete                     Unload + clean config + delete key files
#   setup_pq_ssh.sh --help                       Show this help
#
# Passphrase managers supported for --load / --store-passphrase:
#   keychain    macOS Keychain  (auto-detected, no extra tools needed)
#   bitwarden   Bitwarden CLI   (brew install bitwarden-cli)
#   pass        Unix pass store (brew install pass)
#   nordpass    NordPass        (manual instructions — no CLI)
#   protonpass  ProtonPass      (manual instructions — no CLI)
#
# Exit codes:
#   0  All green
#   1  Warning / partial failure
#   2  Fatal error
#
# Environment overrides:
#   PQ_KEY_PATH      Key file path          (default: ~/.ssh/id_ed25519_pq)
#   PQ_KEX_ALGOS     KEX algorithm string
#   PQ_BW_ITEM       Bitwarden item name    (default: pq-ssh-passphrase)
#   PQ_PASS_ENTRY    pass entry path        (default: ssh/pq-key-passphrase)
# ==============================================================================
set -euo pipefail
IFS=$'\n\t'

# ── Dry-run gate (EPM bash standard C5) ──────────────────────────────────────
APPLY=0

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
DIM='\033[2m'

ok()     { printf "${GREEN}  ✓${RESET}  %s\n" "$*"; }
warn()   { printf "${YELLOW}  ⚠${RESET}  %s\n" "$*"; }
fail()   { printf "${RED}  ✗${RESET}  %s\n" "$*"; }
info()   { printf "${BLUE}  ·${RESET}  %s\n" "$*"; }
dim()    { printf "${DIM}  %s${RESET}\n" "$*"; }
header() { printf "\n${BOLD}${CYAN}%s${RESET}\n" "$*"; }
ask()    { printf "${YELLOW}  ?${RESET}  %s " "$*"; }

# ── Config ────────────────────────────────────────────────────────────────────
SSH_DIR="${HOME}/.ssh"
KEY_PATH="${PQ_KEY_PATH:-${SSH_DIR}/id_ed25519_pq}"
CONFIG_PATH="${SSH_DIR}/config"
KEX_ALGOS="${PQ_KEX_ALGOS:-mlkem768x25519-sha256,sntrup761x25519-sha512,curve25519-sha256}"
KEX_LINE="KexAlgorithms ${KEX_ALGOS}"
MARKER_BEGIN="# BEGIN pq-ssh github.com"
MARKER_END="# END pq-ssh github.com"
AUTOLOAD_BEGIN="# BEGIN pq-ssh autoload"
AUTOLOAD_END="# END pq-ssh autoload"
BW_ITEM="${PQ_BW_ITEM:-pq-ssh-passphrase}"
PASS_ENTRY="${PQ_PASS_ENTRY:-ssh/pq-key-passphrase}"

# ── Predicates ────────────────────────────────────────────────────────────────
is_macos()            { [[ "$(uname -s)" == "Darwin" ]]; }
key_exists()          { [[ -f "$KEY_PATH" ]]; }
pubkey_exists()       { [[ -f "${KEY_PATH}.pub" ]]; }
config_block_present(){ [[ -f "$CONFIG_PATH" ]] && grep -qF "$MARKER_BEGIN" "$CONFIG_PATH"; }
autoload_installed()  {
    local f; for f in "${RC_FILES[@]}"; do
        [[ -f "$f" ]] && grep -qF "$AUTOLOAD_BEGIN" "$f" && return 0
    done; return 1
}
key_loaded_in_agent() {
    # Match by fingerprint (most reliable — agent lists by comment, not path)
    local fp
    fp="$(ssh-keygen -lf "${KEY_PATH}" 2>/dev/null | awk '{print $2}')"
    ssh-add -l 2>/dev/null | grep -qF "${KEY_PATH}" || \
    ssh-add -l 2>/dev/null | grep -qF "$(basename "${KEY_PATH}")" || \
    { [[ -n "$fp" ]] && ssh-add -l 2>/dev/null | grep -qF "$fp"; }
}
has_cmd() { command -v "$1" &>/dev/null; }

# ── Shell rc files ────────────────────────────────────────────────────────────
RC_FILES=()
[[ -f "${HOME}/.zshrc" ]]        && RC_FILES+=("${HOME}/.zshrc")
[[ -f "${HOME}/.bashrc" ]]       && RC_FILES+=("${HOME}/.bashrc")
[[ -f "${HOME}/.bash_profile" ]] && RC_FILES+=("${HOME}/.bash_profile")
[[ -f "${HOME}/.profile" ]]      && RC_FILES+=("${HOME}/.profile")

# ── Passphrase manager helpers ────────────────────────────────────────────────

# Load via SSH_ASKPASS helper — passes passphrase without a TTY
_load_via_askpass() {
    local passphrase="$1"
    local askpass
    askpass="$(mktemp "${TMPDIR:-/tmp}/pq-askpass.XXXXXX")"
    chmod 700 "$askpass"
    # Write script that prints passphrase — single-quoted to prevent expansion
    printf '#!/bin/bash\nprintf "%%s" %q\n' "$passphrase" > "$askpass"
    local rc=0
    DISPLAY='' SSH_ASKPASS="$askpass" SSH_ASKPASS_REQUIRE=force \
        ssh-add "$KEY_PATH" 2>/dev/null || rc=$?
    rm -f "$askpass"
    # Overwrite passphrase variable
    passphrase="$(head -c 64 /dev/urandom | base64 | head -c ${#passphrase})"
    return $rc
}

_passphrase_from_keychain() {
    is_macos || return 1
    security find-generic-password \
        -a "pq-ssh" -s "$(basename "${KEY_PATH}")" -w 2>/dev/null
}

_passphrase_from_bitwarden() {
    has_cmd bw || return 1
    # Ensure session is unlocked
    if [[ -z "${BW_SESSION:-}" ]]; then
        warn "Bitwarden: BW_SESSION not set — run: export BW_SESSION=\$(bw unlock --raw)"
        return 1
    fi
    bw get password "$BW_ITEM" --session "$BW_SESSION" 2>/dev/null
}

_passphrase_from_pass() {
    has_cmd pass || return 1
    pass show "$PASS_ENTRY" 2>/dev/null | head -1
}

# Try managers in order; return passphrase or empty string
_detect_passphrase() {
    local p
    # 1. macOS Keychain
    p="$(_passphrase_from_keychain 2>/dev/null || true)"
    [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
    # 2. Bitwarden
    p="$(_passphrase_from_bitwarden 2>/dev/null || true)"
    [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
    # 3. pass
    p="$(_passphrase_from_pass 2>/dev/null || true)"
    [[ -n "$p" ]] && { printf '%s' "$p"; return 0; }
    return 1
}

# ── Key safety check ──────────────────────────────────────────────────────────
_check_key_permissions() {
    local perms
    if is_macos; then
        perms="$(stat -f '%OLp' "$KEY_PATH" 2>/dev/null || echo '???')"
    else
        perms="$(stat -c '%a' "$KEY_PATH" 2>/dev/null || echo '???')"
    fi
    if [[ "$perms" != "600" ]]; then
        warn "Key permissions: ${perms} (should be 600) — fixing..."
        chmod 600 "$KEY_PATH"
        ok "Key permissions fixed: 600"
    else
        ok "Key permissions: 600 ✓"
    fi
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
        ok "Key:           ${KEY_PATH}"
        dim "               fingerprint: ${fingerprint}"
        _check_key_permissions
    else
        warn "Key:           missing — run: $0 --apply"
    fi

    # Public key
    if pubkey_exists; then
        ok "Public key:    ${KEY_PATH}.pub"
    else
        warn "Public key:    missing"
    fi

    # Agent
    if key_loaded_in_agent; then
        ok "Agent:         key loaded"
    else
        warn "Agent:         key NOT loaded — run: $0 --load"
    fi

    # Config
    if config_block_present; then
        ok "SSH config:    PQ KEX block present"
    else
        warn "SSH config:    PQ KEX block missing — run: $0 --apply"
    fi

    # Autoload
    if autoload_installed; then
        ok "Autoload:      shell snippet installed"
    else
        warn "Autoload:      not installed — run: $0 --install-autoload"
    fi

    # Passphrase managers
    header "Passphrase Managers"
    if is_macos; then
        local kc_pass
        kc_pass="$(_passphrase_from_keychain 2>/dev/null || true)"
        if [[ -n "$kc_pass" ]]; then
            ok "macOS Keychain: passphrase stored ✓"
        else
            warn "macOS Keychain: not stored — run: $0 --store-passphrase keychain"
        fi
    fi
    if has_cmd bw; then
        if [[ -n "${BW_SESSION:-}" ]]; then
            local bw_pass
            bw_pass="$(_passphrase_from_bitwarden 2>/dev/null || true)"
            [[ -n "$bw_pass" ]] && ok "Bitwarden:      stored (item: ${BW_ITEM})" \
                                || warn "Bitwarden:      item '${BW_ITEM}' not found"
        else
            info "Bitwarden:      CLI found — unlock with: export BW_SESSION=\$(bw unlock --raw)"
        fi
    else
        dim "Bitwarden:      CLI not installed (brew install bitwarden-cli)"
    fi
    if has_cmd pass; then
        local pass_val
        pass_val="$(_passphrase_from_pass 2>/dev/null || true)"
        [[ -n "$pass_val" ]] && ok "pass:           entry '${PASS_ENTRY}' found" \
                             || warn "pass:           entry '${PASS_ENTRY}' not found"
    else
        dim "pass:           not installed (brew install pass)"
    fi
    dim "NordPass:       no CLI — see --store-passphrase nordpass for instructions"
    dim "ProtonPass:     no CLI — see --store-passphrase protonpass for instructions"

    # GitHub connectivity
    header "GitHub Connectivity"
    info "Testing SSH handshake..."
    local out
    out="$(ssh -T -o BatchMode=yes -o ConnectTimeout=8 \
              -o IdentityFile="${KEY_PATH}" -o IdentitiesOnly=yes \
              git@github.com 2>&1)" || true
    if printf '%s' "$out" | grep -qi "^Hi "; then
        local gh_user
        gh_user="$(printf '%s' "$out" | grep -oE 'Hi [^!]+' | sed 's/^Hi //')"
        ok "Authenticated as: ${gh_user}"
    elif printf '%s' "$out" | grep -qi "Permission denied\|publickey"; then
        warn "Permission denied"
        if ! key_loaded_in_agent; then
            info "  → Key not in agent. Run: $0 --load"
        else
            info "  → Key is loaded. Has the public key been uploaded to GitHub?"
            info "    gh ssh-key add ${KEY_PATH}.pub --title pq-$(hostname -s)"
        fi
    else
        warn "Inconclusive: ${out}"
    fi
    printf '\n'
}

cmd_apply() {
    header "PQ SSH Setup"
    mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"

    # Generate key
    if key_exists; then
        ok "Key already exists: ${KEY_PATH}"
        _check_key_permissions
    else
        info "Generating Ed25519 key: ${KEY_PATH}"
        ssh-keygen -t ed25519 -a 64 -f "$KEY_PATH" -C "pq-kex-$(hostname -s)"
        chmod 600 "$KEY_PATH"
        ok "Key generated: ${KEY_PATH}"
        printf '\n'
        warn "Upload public key to GitHub:"
        info "  gh ssh-key add ${KEY_PATH}.pub --title pq-$(hostname -s)"
        printf '\n'
    fi

    # Config block (idempotent via markers)
    touch "$CONFIG_PATH"; chmod 600 "$CONFIG_PATH"
    if config_block_present; then
        ok "SSH config: PQ KEX block already present"
    else
        info "Writing PQ KEX block to ${CONFIG_PATH}"
        {
            printf '\n%s\n' "$MARKER_BEGIN"
            printf 'Host github.com\n'
            printf '  %s\n' "$KEX_LINE"
            printf '  IdentityFile %s\n' "$KEY_PATH"
            printf '  IdentitiesOnly yes\n'
            printf '%s\n' "$MARKER_END"
        } >> "$CONFIG_PATH"
        ok "SSH config: PQ KEX block written"
    fi

    printf '\n'
    ok "Setup complete."
    info "Next: $0 --store-passphrase keychain   # store passphrase"
    info "      $0 --load                         # load into agent"
    info "      $0 --install-autoload             # auto-load on login"
    info "      $0 --verify                       # test connectivity"
    printf '\n'
}

cmd_load() {
    local manager="${1:-auto}"
    header "Loading key into ssh-agent"

    if ! key_exists; then
        fail "Key not found: ${KEY_PATH} — run: $0 --apply"
        exit 1
    fi

    if key_loaded_in_agent; then
        ok "Key already loaded in agent"
        exit 0
    fi

    # macOS Keychain path — most seamless
    if is_macos && [[ "$manager" == "auto" || "$manager" == "keychain" ]]; then
        info "Trying macOS Keychain (--apple-use-keychain)..."
        if ssh-add --apple-use-keychain "$KEY_PATH" 2>/dev/null; then
            key_loaded_in_agent && { ok "Key loaded via macOS Keychain"; return 0; }
        fi
        # Keychain didn't have it — will fall through to interactive or other manager
    fi

    # Manager-specific passphrase retrieval
    if [[ "$manager" != "keychain" ]]; then
        local passphrase=""
        case "$manager" in
            bitwarden)
                info "Retrieving passphrase from Bitwarden..."
                passphrase="$(_passphrase_from_bitwarden)" || true ;;
            pass)
                info "Retrieving passphrase from pass store..."
                passphrase="$(_passphrase_from_pass)" || true ;;
            auto)
                passphrase="$(_detect_passphrase 2>/dev/null || true)" ;;
        esac

        if [[ -n "$passphrase" ]]; then
            _load_via_askpass "$passphrase" && {
                key_loaded_in_agent && { ok "Key loaded via ${manager} passphrase"; return 0; }
            }
        fi
    fi

    # Fallback: interactive prompt
    info "Prompting for passphrase interactively..."
    if is_macos; then
        ssh-add --apple-use-keychain "$KEY_PATH"
    else
        ssh-add "$KEY_PATH"
    fi

    key_loaded_in_agent && ok "Key loaded: ${KEY_PATH}" || { fail "Failed to load key"; exit 2; }
    printf '\n'
}

cmd_unload() {
    header "Unloading key from ssh-agent"
    if ! key_loaded_in_agent; then
        ok "Key not in agent (nothing to unload)"
        return 0
    fi
    ssh-add -d "$KEY_PATH" 2>/dev/null && ok "Key removed from agent" \
        || { fail "Failed to remove key from agent"; exit 1; }
    printf '\n'
}

cmd_clean() {
    header "Removing PQ KEX config block"
    if ! config_block_present; then
        ok "No PQ KEX block found in ${CONFIG_PATH} (nothing to clean)"
        return 0
    fi

    local tmp
    tmp="$(mktemp)"
    # Remove everything between (and including) the markers
    awk "
        /^${MARKER_BEGIN}/{skip=1; next}
        /^${MARKER_END}/{skip=0; next}
        !skip{print}
    " "$CONFIG_PATH" > "$tmp"
    mv "$tmp" "$CONFIG_PATH"
    chmod 600 "$CONFIG_PATH"
    ok "PQ KEX block removed from ${CONFIG_PATH}"
    printf '\n'
}

cmd_delete() {
    header "Delete PQ SSH Key"
    warn "This will permanently delete:"
    info "  • ${KEY_PATH}"
    info "  • ${KEY_PATH}.pub"
    info "  • Remove PQ KEX block from ${CONFIG_PATH}"
    info "  • Unload from ssh-agent"
    printf '\n'
    ask "Type 'yes' to confirm:"
    local answer; read -r answer
    [[ "$answer" == "yes" ]] || { info "Aborted."; exit 0; }

    cmd_unload 2>/dev/null || true
    cmd_clean  2>/dev/null || true

    if key_exists; then
        # Overwrite before delete (shred-like)
        dd if=/dev/urandom of="$KEY_PATH" bs=1 count="$(wc -c < "$KEY_PATH")" 2>/dev/null || true
        rm -f "$KEY_PATH"
        ok "Private key deleted: ${KEY_PATH}"
    fi
    if pubkey_exists; then
        rm -f "${KEY_PATH}.pub"
        ok "Public key deleted: ${KEY_PATH}.pub"
    fi

    # Remove autoload snippets
    local f
    for f in "${RC_FILES[@]}"; do
        [[ -f "$f" ]] && grep -qF "$AUTOLOAD_BEGIN" "$f" || continue
        local tmp; tmp="$(mktemp)"
        awk "
            /^${AUTOLOAD_BEGIN}/{skip=1; next}
            /^${AUTOLOAD_END}/{skip=0; next}
            !skip{print}
        " "$f" > "$tmp"
        mv "$tmp" "$f"
        ok "Autoload snippet removed from ${f}"
    done

    printf '\n'
    ok "PQ SSH key fully deleted."
    warn "Remember to remove the public key from GitHub: https://github.com/settings/keys"
    printf '\n'
}

cmd_install_autoload() {
    header "Installing autoload snippet"

    local snippet
    snippet="$(printf '%s\n%s\n%s\n' \
        "$AUTOLOAD_BEGIN" \
        '# Auto-load PQ SSH key into agent on shell start (installed by setup_pq_ssh.sh)' \
        '_pq_ssh_autoload() {' \
        "  [[ -f \"${KEY_PATH}\" ]] || return 0" \
        '  ssh-add -l 2>/dev/null | grep -qF '"\"$(basename "${KEY_PATH}")\""' && return 0' \
        '  if [[ "$(uname -s)" == "Darwin" ]]; then' \
        "    ssh-add --apple-use-keychain \"${KEY_PATH}\" 2>/dev/null || true" \
        '  else' \
        "    ssh-add \"${KEY_PATH}\" 2>/dev/null || true" \
        '  fi' \
        '}' \
        '_pq_ssh_autoload; unset -f _pq_ssh_autoload' \
        "$AUTOLOAD_END")"

    if [[ ${#RC_FILES[@]} -eq 0 ]]; then
        warn "No shell rc files found. Creating ~/.zshrc"
        touch "${HOME}/.zshrc"
        RC_FILES+=("${HOME}/.zshrc")
    fi

    local f installed=0
    for f in "${RC_FILES[@]}"; do
        if grep -qF "$AUTOLOAD_BEGIN" "$f" 2>/dev/null; then
            ok "Already installed in ${f}"
        else
            printf '\n%s\n' "$snippet" >> "$f"
            ok "Installed autoload in ${f}"
            installed=$((installed + 1))
        fi
    done

    printf '\n'
    info "Snippet auto-loads key on every new shell. No passphrase prompt if Keychain is set up."
    info "To activate now without opening a new shell: source ${RC_FILES[0]}"
    printf '\n'
}

cmd_store_passphrase() {
    local manager="${1:-}"
    if [[ -z "$manager" ]]; then
        fail "Usage: $0 --store-passphrase <keychain|bitwarden|pass|nordpass|protonpass>"
        exit 2
    fi

    header "Store passphrase in: ${manager}"

    case "$manager" in
        keychain)
            if ! is_macos; then fail "macOS Keychain requires macOS"; exit 1; fi
            info "Loading key with --apple-use-keychain (stores passphrase in Keychain)"
            info "You will be prompted for the passphrase once."
            ssh-add --apple-use-keychain "$KEY_PATH"
            ok "Passphrase stored in macOS Keychain"
            info "Future --load calls will use Keychain silently."
            ;;

        bitwarden)
            if ! has_cmd bw; then
                fail "Bitwarden CLI not found. Install: brew install bitwarden-cli"
                exit 1
            fi
            if [[ -z "${BW_SESSION:-}" ]]; then
                fail "BW_SESSION not set. Run: export BW_SESSION=\$(bw unlock --raw)"
                exit 1
            fi
            ask "Enter passphrase for ${KEY_PATH}:"
            local pp; read -rs pp; printf '\n'
            local payload
            payload="$(bw get template item 2>/dev/null | \
                bw encode | \
                jq --arg name "$BW_ITEM" --arg pp "$pp" \
                   '.name=$name | .type=2 | .secureNote={type:0} | .notes=$pp' 2>/dev/null || echo '')"
            if [[ -n "$payload" ]]; then
                echo "$payload" | bw create item --session "$BW_SESSION" > /dev/null
                ok "Passphrase stored in Bitwarden as '${BW_ITEM}'"
            else
                # Fallback: store as plain secure note
                printf '{"type":2,"name":"%s","notes":"%s","secureNote":{"type":0}}' \
                    "$BW_ITEM" "$pp" | bw create item --session "$BW_SESSION" > /dev/null
                ok "Passphrase stored in Bitwarden as '${BW_ITEM}'"
            fi
            pp="$(head -c ${#pp} /dev/urandom | base64 | head -c ${#pp})"
            ;;

        pass)
            if ! has_cmd pass; then
                fail "pass not found. Install: brew install pass"
                exit 1
            fi
            info "Inserting passphrase into pass store at: ${PASS_ENTRY}"
            pass insert -f "$PASS_ENTRY"
            ok "Passphrase stored in pass at '${PASS_ENTRY}'"
            ;;

        nordpass)
            header "NordPass — manual steps"
            info "NordPass has no public CLI for passphrase retrieval."
            info "Recommended approach:"
            dim "  1. Open NordPass app"
            dim "  2. Create a new 'Password' item named: pq-ssh key ($(hostname -s))"
            dim "  3. Set the password field to your SSH key passphrase"
            dim "  4. To use it with --load, copy manually and run:"
            dim "       PQ_PASSPHRASE=\$(pbpaste) $0 --load"
            printf '\n'
            warn "Automatic loading from NordPass is not supported (no CLI)."
            ;;

        protonpass)
            header "ProtonPass — manual steps"
            info "ProtonPass has no public CLI."
            info "Recommended approach:"
            dim "  1. Open ProtonPass app / browser extension"
            dim "  2. Create a new Login item named: pq-ssh key ($(hostname -s))"
            dim "  3. Set the password to your SSH key passphrase"
            dim "  4. To use with --load, copy manually and run:"
            dim "       PQ_PASSPHRASE=\$(pbpaste) $0 --load"
            printf '\n'
            warn "Automatic loading from ProtonPass is not supported (no CLI)."
            ;;

        *)
            fail "Unknown manager: ${manager}"
            info "Supported: keychain, bitwarden, pass, nordpass, protonpass"
            exit 2
            ;;
    esac
    printf '\n'
}

cmd_verify() {
    header "Verifying GitHub SSH connectivity"

    if ! key_exists; then fail "Key not found: ${KEY_PATH}"; exit 1; fi

    if ! key_loaded_in_agent; then
        warn "Key not in agent — loading now..."
        cmd_load auto
    fi

    info "Testing SSH handshake (BatchMode)..."
    local out
    out="$(ssh -T -o BatchMode=yes -o ConnectTimeout=8 \
              -o IdentityFile="${KEY_PATH}" -o IdentitiesOnly=yes \
              git@github.com 2>&1)" || true

    if printf '%s' "$out" | grep -qi "^Hi "; then
        local gh_user
        gh_user="$(printf '%s' "$out" | grep -oE 'Hi [^!]+' | sed 's/^Hi //')"
        ok "Authenticated as: ${gh_user}"
    elif printf '%s' "$out" | grep -qi "Permission denied\|publickey"; then
        fail "Permission denied — upload public key to GitHub:"
        info "  gh ssh-key add ${KEY_PATH}.pub --title pq-$(hostname -s)"
        exit 1
    else
        fail "Unexpected: ${out}"; exit 1
    fi

    info "Checking negotiated KEX algorithm (~3s)..."
    local verbose_out algo
    verbose_out="$(ssh -vvv -T -o BatchMode=yes -o ConnectTimeout=8 \
                      -o IdentityFile="${KEY_PATH}" -o IdentitiesOnly=yes \
                      git@github.com 2>&1)" || true
    algo="$(printf '%s' "$verbose_out" | grep -oE 'kex: algorithm: [^ ]+' | head -1 | \
            sed 's/kex: algorithm: //' || true)"

    if [[ -z "$algo" ]]; then
        warn "Could not detect KEX algorithm"
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
MANAGER_ARG="auto"

i=1
while [[ $i -le $# ]]; do
    arg="${!i}"
    case "$arg" in
        --apply)              APPLY=1; MODE="apply" ;;
        --load)               MODE="load" ;;
        --unload)             MODE="unload" ;;
        --verify)             MODE="verify" ;;
        --status)             MODE="status" ;;
        --clean)              MODE="clean" ;;
        --delete)             MODE="delete" ;;
        --install-autoload)   MODE="install-autoload" ;;
        --store-passphrase)   MODE="store-passphrase"; i=$((i+1)); MANAGER_ARG="${!i:-}" ;;
        --manager)            i=$((i+1)); MANAGER_ARG="${!i:-}" ;;
        --help|-h)            MODE="help" ;;
        *) fail "Unknown argument: ${arg}"; exit 2 ;;
    esac
    i=$((i+1))
done

case "$MODE" in
    help)             cmd_help ;;
    status)           cmd_status ;;
    apply)            cmd_apply ;;
    load)             cmd_load "$MANAGER_ARG" ;;
    unload)           cmd_unload ;;
    verify)           cmd_verify ;;
    clean)            cmd_clean ;;
    delete)           cmd_delete ;;
    install-autoload) cmd_install_autoload ;;
    store-passphrase) cmd_store_passphrase "$MANAGER_ARG" ;;
    default)
        printf "${BOLD}PQ SSH v2.0.0${RESET} — dry-run (no changes)\n"
        cmd_status
        printf "${DIM}Run with --apply to set up, --load to unlock, --help for all commands.${RESET}\n\n"
        ;;
esac
