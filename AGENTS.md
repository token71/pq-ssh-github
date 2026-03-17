# AGENTS.md — AI Agent Context

## Role of This Repo

`pq_ssh_github_regen` manages post-quantum SSH key generation, lifecycle, and GitHub integration.
It provides a self-contained toolchain for generating Ed25519/ECDSA keys, storing passphrases in
macOS Keychain, loading keys into `ssh-agent`, and wiring subcommands into the `ep` CLI dispatcher.

---

## Script Structure

### `setup_pq_ssh.sh` (main script → installed as `~/.bin/pq-ssh`)

Entry point. Supports the following flags:

| Flag | Description |
|------|-------------|
| `--apply` | Full setup: generate key, write SSH config, store passphrase, load agent |
| `--load [key]` | Load key into ssh-agent (prompts or reads from Keychain) |
| `--unload` | Remove all keys from ssh-agent |
| `--verify` | Test GitHub SSH authentication |
| `--status` | Show agent key count, loaded fingerprints, config state |
| `--store-passphrase [keychain\|env]` | Store passphrase in Keychain or export to env |
| `--clean` | Remove generated key files and SSH config block |
| `--delete` | Full teardown: clean + remove from Keychain + unload agent |
| `--dry-run` | Parse and echo actions without executing (combine with any flag) |
| `--help` | Print usage |

### `lib/ep-integration.sh`

Sourced by `install.sh` into `~/.zshrc` / `~/.bashrc`.
Wraps the `ep` command to intercept `ssh*` subcommands and delegate to `pq-ssh`.
Idempotent — safe to source multiple times.

Autoload markers:
```
# BEGIN pq-ssh ep-integration
# END pq-ssh ep-integration
```

### `install.sh`

- Copies `setup_pq_ssh.sh` → `~/.bin/pq-ssh` (chmod +x)
- Appends `ep-integration.sh` source line between markers in `~/.zshrc` / `~/.bashrc`
- Idempotent: checks for markers before inserting

---

## EPM Standards

Every bash file **must** include:

```bash
#!/opt/homebrew/bin/bash
# Version: X.Y.Z
set -euo pipefail
IFS=$'\n\t'
```

- `APPLY=0` pattern: default dry-run, set `APPLY=1` only when `--apply` / explicit write flags passed
- Never use `/bin/bash` — always `/opt/homebrew/bin/bash` for Homebrew-managed Bash 5+
- Functions prefixed with `_pq_ssh_` to avoid namespace collisions

---

## Key File Paths

| Variable | Default Value |
|----------|---------------|
| `KEY_PATH` | `~/.ssh/id_ed25519_github_pq` |
| `CONFIG_PATH` | `~/.ssh/config` |
| `BIN_PATH` | `~/.bin/pq-ssh` |
| `AUTOLOAD_BEGIN` | `# BEGIN pq-ssh ep-integration` |
| `AUTOLOAD_END` | `# END pq-ssh ep-integration` |

---

## Security Rules

- **Never commit private keys.** `~/.ssh/id_ed25519_github_pq` must never appear in git history.
- `.gitignore` must exclude `*.pem`, `id_*`, and any file matching `~/.ssh/*`.
- Passphrases must never be echoed to stdout or written to disk in plaintext.
- Keychain access uses `security add-generic-password` / `security find-generic-password`.

---

## How to Test Changes

```bash
# Dry-run any flag (no writes occur):
pq-ssh --dry-run --apply
pq-ssh --dry-run --load
pq-ssh --dry-run --clean

# Verify GitHub auth after load:
pq-ssh --verify

# Check current agent state:
pq-ssh --status

# Test ep integration (after sourcing):
ep ssh
ep ssh-load
ep ssh-verify
```

---

## Integration Points

| Point | Detail |
|-------|--------|
| `ep` CLI | Wrapped via `lib/ep-integration.sh`; `ep ssh*` delegates to `pq-ssh` |
| `~/.bin/pq-ssh` | Installed binary; must be on `$PATH` |
| Shell RC files | `~/.zshrc` and/or `~/.bashrc` — source line injected between markers |
| macOS Keychain | Passphrase stored under service `pq-ssh` / account `github` |
| `ssh-agent` | Keys loaded via `ssh-add`; unloaded with `ssh-add -D` |
| GitHub API | Public key uploaded via `gh ssh-key add` or manual paste |
