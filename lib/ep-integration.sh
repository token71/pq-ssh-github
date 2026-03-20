#!/opt/homebrew/bin/bash
# Version: 1.0.0
# ep-integration.sh — pq-ssh subcommands for the ep CLI
# Source this file (via install.sh) to add ep ssh* subcommands
# BEGIN pq-ssh ep-integration
# NOTE: do NOT set -e here — this file is sourced into interactive shells

# Wrap ep to intercept ssh subcommands
_pq_ssh_ep_wrap() {
  case "${1:-}" in
    ssh)         pq-ssh --status ;;
    ssh-load)    pq-ssh --load "${@:2}" ;;
    ssh-unload)  pq-ssh --unload ;;
    ssh-verify)  pq-ssh --verify ;;
    ssh-setup)   pq-ssh --apply ;;
    ssh-store)   pq-ssh --store-passphrase "${2:-keychain}" ;;
    *)           command ep "$@" 2>/dev/null || ep "$@" ;;
  esac
}

# Only wrap if ep exists and we haven't already wrapped
if command -v ep &>/dev/null && [[ "$(type -t ep)" != "function" ]]; then
  ep() { _pq_ssh_ep_wrap "$@"; }
fi
# END pq-ssh ep-integration
