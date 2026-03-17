# CHANGELOG

All notable changes to `pq_ssh_github_regen` are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [2.0.1] — 2026-03-17

### Fixed
- `key_loaded_in_agent`: fingerprint matching now compares normalized SHA256 hashes from
  `ssh-add -l` output against `ssh-keygen -lf` output, fixing false negatives when key
  was loaded but reported as missing.

---

## [2.0.0] — 2026-03-17

### Added
- Full key lifecycle: `--apply`, `--load`, `--unload`, `--clean`, `--delete` flags
- `lib/ep-integration.sh`: wraps `ep` CLI to expose `ssh*` subcommands
- `install.sh`: idempotent installer with BEGIN/END marker injection into shell RC files
- `--store-passphrase [keychain|env]`: flexible passphrase storage backends
- Autoload markers (`# BEGIN pq-ssh ep-integration` / `# END pq-ssh ep-integration`)
- `--dry-run` mode for all write operations (APPLY=0 default pattern)

### Changed
- Refactored into manager functions: `_agent_manager`, `_config_manager`, `_key_manager`
- All subcommands route through a single dispatch table

---

## [1.0.0] — 2026-03-17

### Added
- Production-ready rewrite following EPM standards:
  - `#!/opt/homebrew/bin/bash` shebang
  - `set -euo pipefail` + `IFS=$'\n\t'`
  - `# Version: X.Y.Z` header on all scripts
- `--apply`: end-to-end key generation, SSH config write, Keychain store, agent load
- `--load`: load existing key into ssh-agent
- `--verify`: `ssh -T git@github.com` authentication test
- `--status`: agent state + loaded fingerprints + config presence
- `--help`: usage text

---

## [0.1.0] — initial

### Added
- Basic Ed25519 key generation (`ssh-keygen`)
- Minimal SSH config block for `github.com`
- Manual passphrase entry prompt
